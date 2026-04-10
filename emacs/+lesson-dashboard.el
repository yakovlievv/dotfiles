;;; +lesson-dashboard.el --- Lesson Dashboard for tutoring -*- lexical-binding: t; -*-

(defvar lesson-dashboard--lessons nil
  "List of today's lessons. Each element is a plist:
  (:title :time :end-time :file :heading)")

(defvar lesson-dashboard--timer nil
  "Timer for updating the lesson clock display.")

(defvar lesson-dashboard--current-index 0
  "Index of the currently displayed lesson.")

(defvar lesson-dashboard--dirty nil
  "Non-nil if the dashboard content has been modified.")

(defvar lesson-dashboard--content-start nil
  "Buffer position where editable lesson content begins.")

(defvar lesson-dashboard-buffer-name "*Lesson Dashboard*"
  "Name of the lesson dashboard buffer.")


(defun lesson-dashboard--find-lesson-files ()
  "Find all org files with :lesson_plan: filetag."
  (let ((files (directory-files-recursively "~/org/roam/" "\\.org$"))
        (result '()))
    (dolist (f files)
      (with-temp-buffer
        (insert-file-contents f nil 0 500)
        (when (re-search-forward "^#\\+filetags:.*:lesson_plan:" nil t)
          (goto-char (point-min))
          (let ((title (when (re-search-forward "^#\\+title:\\s-*\\(.*\\)" nil t)
                         (match-string 1))))
            (push (cons title f) result)))))
    (nreverse result)))

(defun lesson-dashboard--find-todays-lessons ()
  "Scan lesson plan files for lessons scheduled today.
Matches headings like:
  * Lesson 9 <2026-03-26 Thu 18:15-19:15>
  * Lesson 9 <2026-03-26 Thu 18:15>"
  (let ((today (format-time-string "%Y-%m-%d"))
        (files (lesson-dashboard--find-lesson-files))
        (lessons '()))
    (dolist (tf files)
      (let ((title (car tf))
            (file (cdr tf)))
        (with-current-buffer (find-file-noselect file)
          (save-excursion
            (goto-char (point-min))
            (while (re-search-forward
                    (concat "^\\(\\* Lesson [0-9]+\\)"
                            " <" (regexp-quote today)
                            " [A-Za-z]+ \\([0-9]+:[0-9]+\\)"
                            "\\(?:-\\([0-9]+:[0-9]+\\)\\)?>")
                    nil t)
              (let ((heading (match-string-no-properties 1))
                    (time-str (match-string-no-properties 2))
                    (end-str (match-string-no-properties 3)))
                (push (list :title title
                            :time time-str
                            :end-time end-str
                            :file file
                            :heading heading)
                      lessons)))))))
    (sort lessons (lambda (a b)
                    (string< (plist-get a :time)
                             (plist-get b :time))))))

(defun lesson-dashboard--heading-bounds (file heading)
  "In FILE buffer, find HEADING and return (BEG . END) of its subtree."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-min))
      (when (search-forward heading nil t)
        (goto-char (line-beginning-position))
        (let ((beg (point)))
          (forward-line 1)
          (let ((end (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max))))
            (cons beg end)))))))

(defun lesson-dashboard--timer-suffix (lesson)
  "Return a timer string for LESSON based on current time."
  (let* ((start-str (plist-get lesson :time))
         (end-str (plist-get lesson :end-time))
         (start-min (lesson-dashboard--parse-hm start-str))
         (end-min (lesson-dashboard--parse-hm end-str))
         (now-min (+ (* 60 (string-to-number (format-time-string "%H")))
                     (string-to-number (format-time-string "%M")))))
    (cond
     ((null end-min)
      (if (< now-min start-min)
          (lesson-dashboard--format-duration (- start-min now-min))
        nil))
     ((< now-min start-min)
      (lesson-dashboard--format-duration (- start-min now-min)))
     ((< now-min end-min)
      (lesson-dashboard--format-duration (- end-min now-min)))
     (t "0m"))))

(defun lesson-dashboard--render-tabs ()
  "Insert the tab bar into the buffer. Returns position after tabs."
  (let ((start (point))
        (active-timer-str nil))
    (insert "  ")
    (dotimes (i (length lesson-dashboard--lessons))
      (let* ((lesson (nth i lesson-dashboard--lessons))
             (title (plist-get lesson :title))
             (time (plist-get lesson :time))
             (end-time (plist-get lesson :end-time))
             (active (= i lesson-dashboard--current-index))
             (time-range (if end-time
                             (format "%s-%s" time end-time)
                           time))
             (label (format " %s %s " title time-range))
             (f (if active
                    '(:background "#89b4fa" :foreground "#1e1e2e" :weight normal :underline nil :height 1.0)
                  '(:background "#313244" :foreground "#cdd6f4" :weight normal :underline nil :height 1.0))))
        (when active
          (setq active-timer-str (lesson-dashboard--timer-suffix lesson)))
        (insert (propertize label 'face f 'font-lock-face f))
        (insert " ")))
    ;; Right-align the timer, only if it fits on the same line
    (when active-timer-str
      (let* ((timer-label (format " %s " active-timer-str))
             (used (- (point) (line-beginning-position)))
             (padding (- (1- (window-body-width)) used (length timer-label))))
        (when (> padding 0)
          (insert (make-string padding ?\s))
          (insert (propertize timer-label
                              'face '(:background "#cba6f7" :foreground "#1e1e2e" :weight normal :height 1.0)
                              'font-lock-face '(:background "#cba6f7" :foreground "#1e1e2e" :weight normal :height 1.0))))))
    (insert "\n\n")
    ;; Mark tab region as read-only and already fontified so org-mode won't override faces
    (add-text-properties start (point) '(read-only t fontified t))
    (point)))

(defun lesson-dashboard--load-content ()
  "Load the content of the currently selected lesson."
  (let* ((lesson (nth lesson-dashboard--current-index lesson-dashboard--lessons))
         (file (plist-get lesson :file))
         (heading (plist-get lesson :heading))
         (bounds (lesson-dashboard--heading-bounds file heading)))
    (when bounds
      (with-current-buffer (find-file-noselect file)
        (buffer-substring-no-properties (car bounds) (cdr bounds))))))

(defun lesson-dashboard--save-content ()
  "Save the editable content back to the source file."
  (when (and lesson-dashboard--lessons lesson-dashboard--dirty)
    (let* ((lesson (nth lesson-dashboard--current-index lesson-dashboard--lessons))
           (file (plist-get lesson :file))
           (heading (plist-get lesson :heading))
           (bounds (lesson-dashboard--heading-bounds file heading))
           (new-content (buffer-substring-no-properties
                         lesson-dashboard--content-start (point-max))))
      (when bounds
        (with-current-buffer (find-file-noselect file)
          (save-excursion
            (goto-char (car bounds))
            (delete-region (car bounds) (cdr bounds))
            (insert new-content)
            (unless (bolp) (insert "\n"))
            (save-buffer)))))
    (setq lesson-dashboard--dirty nil)))

(defun lesson-dashboard--mark-dirty (&rest _)
  "Mark dashboard content as modified."
  (setq lesson-dashboard--dirty t))

(defun lesson-dashboard--snap-cursor ()
  "Clamp cursor so it cannot enter the tab bar region."
  (when (and (eq major-mode 'lesson-dashboard-mode)
             (markerp lesson-dashboard--content-start)
             (marker-position lesson-dashboard--content-start)
             (< (point) lesson-dashboard--content-start))
    (goto-char lesson-dashboard--content-start)))

(defun lesson-dashboard--refresh ()
  "Refresh the dashboard display with current lesson."
  (let ((inhibit-read-only t))
    (remove-hook 'after-change-functions #'lesson-dashboard--mark-dirty t)
    (erase-buffer)
    (lesson-dashboard--render-tabs)
    (setq lesson-dashboard--content-start (point-marker))
    (let ((content (lesson-dashboard--load-content)))
      (when content (insert content)))
    (setq lesson-dashboard--dirty nil)
    (add-hook 'after-change-functions #'lesson-dashboard--mark-dirty nil t)
    (goto-char lesson-dashboard--content-start)))

(defun lesson-dashboard-next ()
  "Switch to the next lesson tab."
  (interactive)
  (if (or (null lesson-dashboard--lessons)
          (>= lesson-dashboard--current-index
              (1- (length lesson-dashboard--lessons))))
      (message "No next lessons.")
    (lesson-dashboard--save-content)
    (setq lesson-dashboard--current-index (1+ lesson-dashboard--current-index))
    (lesson-dashboard--refresh)))

(defun lesson-dashboard-prev ()
  "Switch to the previous lesson tab."
  (interactive)
  (if (or (null lesson-dashboard--lessons)
          (<= lesson-dashboard--current-index 0))
      (message "No previous lessons.")
    (lesson-dashboard--save-content)
    (setq lesson-dashboard--current-index (1- lesson-dashboard--current-index))
    (lesson-dashboard--refresh)))

(defun lesson-dashboard--lesson-number (heading)
  "Extract the lesson number from HEADING like \"* Lesson 5\"."
  (when (string-match "\\* Lesson \\([0-9]+\\)" heading)
    (string-to-number (match-string 1 heading))))

(defun lesson-dashboard--heading-exists-p (file heading)
  "Return non-nil if HEADING exists in FILE."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-min))
      (search-forward heading nil t))))

(defun lesson-dashboard-next-lesson ()
  "Navigate to the next lesson within the current tab's file."
  (interactive)
  (let* ((lesson (nth lesson-dashboard--current-index lesson-dashboard--lessons))
         (file (plist-get lesson :file))
         (heading (plist-get lesson :heading))
         (num (lesson-dashboard--lesson-number heading)))
    (if (null num)
        (message "Cannot determine lesson number.")
      (let ((next-heading (format "* Lesson %d" (1+ num))))
        (if (not (lesson-dashboard--heading-exists-p file next-heading))
            (message "No next lesson in this file.")
          (lesson-dashboard--save-content)
          (plist-put lesson :heading next-heading)
          (lesson-dashboard--refresh))))))

(defun lesson-dashboard-prev-lesson ()
  "Navigate to the previous lesson within the current tab's file."
  (interactive)
  (let* ((lesson (nth lesson-dashboard--current-index lesson-dashboard--lessons))
         (file (plist-get lesson :file))
         (heading (plist-get lesson :heading))
         (num (lesson-dashboard--lesson-number heading)))
    (if (or (null num) (<= num 1))
        (message "No previous lesson in this file.")
      (let ((prev-heading (format "* Lesson %d" (1- num))))
        (if (not (lesson-dashboard--heading-exists-p file prev-heading))
            (message "No previous lesson in this file.")
          (lesson-dashboard--save-content)
          (plist-put lesson :heading prev-heading)
          (lesson-dashboard--refresh))))))

(defun lesson-dashboard-save ()
  "Save the current lesson content."
  (interactive)
  (lesson-dashboard--save-content)
  (message "Lesson saved."))

(defun lesson-dashboard--kill-query ()
  "Prompt to save before killing the lesson dashboard buffer."
  (if (not lesson-dashboard--dirty)
      t
    (let ((answer (read-char-choice
                   "Lesson dashboard modified. [s]ave, [d]iscard, [c]ancel? "
                   '(?s ?d ?c))))
      (pcase answer
        (?s (lesson-dashboard--save-content) t)
        (?d t)
        (?c nil)))))

(defun lesson-dashboard-quit ()
  "Save and quit the lesson dashboard."
  (interactive)
  (lesson-dashboard--save-content)
  (kill-buffer (current-buffer)))

(defun lesson-dashboard--protect-tabs (beg end _old-len)
  "Re-apply fontified property on tab region so org font-lock won't touch it."
  (when (and (markerp lesson-dashboard--content-start)
             (marker-position lesson-dashboard--content-start)
             (< beg (marker-position lesson-dashboard--content-start)))
    (with-silent-modifications
      (add-text-properties (point-min) (marker-position lesson-dashboard--content-start)
                           '(fontified t)))))

(defun lesson-dashboard--parse-hm (hm-str)
  "Parse \"HH:MM\" string into total minutes since midnight."
  (when (and hm-str (string-match "\\([0-9]+\\):\\([0-9]+\\)" hm-str))
    (+ (* 60 (string-to-number (match-string 1 hm-str)))
       (string-to-number (match-string 2 hm-str)))))

(defun lesson-dashboard--format-duration (minutes)
  "Format MINUTES as \"Xh Ym\" or \"Ym\"."
  (let ((h (/ minutes 60))
        (m (% minutes 60)))
    (if (> h 0)
        (format "%dh %dm" h m)
      (format "%dm" m))))

(defun lesson-dashboard--refresh-tabs ()
  "Re-render only the tab bar without touching content."
  (when (and (markerp lesson-dashboard--content-start)
             (marker-position lesson-dashboard--content-start))
    (let ((inhibit-read-only t))
      (remove-hook 'after-change-functions #'lesson-dashboard--mark-dirty t)
      (save-excursion
        (delete-region (point-min) lesson-dashboard--content-start)
        (goto-char (point-min))
        (lesson-dashboard--render-tabs)
        (set-marker lesson-dashboard--content-start (point)))
      (add-hook 'after-change-functions #'lesson-dashboard--mark-dirty nil t))))

(defun lesson-dashboard--update-timer ()
  "Re-render tabs to update the timer display."
  (when-let ((buf (get-buffer lesson-dashboard-buffer-name)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (lesson-dashboard--refresh-tabs)))))

(defun lesson-dashboard--start-timer ()
  "Start the timer for updating the lesson clock."
  (lesson-dashboard--stop-timer)
  (setq lesson-dashboard--timer
        (run-at-time t 30 #'lesson-dashboard--update-timer)))

(defun lesson-dashboard--stop-timer ()
  "Stop the lesson clock timer."
  (when lesson-dashboard--timer
    (cancel-timer lesson-dashboard--timer)
    (setq lesson-dashboard--timer nil)))

(defun lesson-dashboard-open-link-split ()
  "Open org link at point in a vertical split."
  (interactive)
  (org-open-link-in-vsplit))

(define-derived-mode lesson-dashboard-mode org-mode "LessonDash"
  "Major mode for the lesson dashboard."
  (evil-local-set-key 'normal (kbd "C-c C-o") #'lesson-dashboard-open-link-split)
  (evil-local-set-key 'normal (kbd "C-h") #'lesson-dashboard-prev)
  (evil-local-set-key 'normal (kbd "C-l") #'lesson-dashboard-next)
  (evil-local-set-key 'insert (kbd "C-h") #'lesson-dashboard-prev)
  (evil-local-set-key 'insert (kbd "C-l") #'lesson-dashboard-next)
  (evil-local-set-key 'normal (kbd "C-j") #'lesson-dashboard-next-lesson)
  (evil-local-set-key 'normal (kbd "C-k") #'lesson-dashboard-prev-lesson)
  (evil-local-set-key 'insert (kbd "C-j") #'lesson-dashboard-next-lesson)
  (evil-local-set-key 'insert (kbd "C-k") #'lesson-dashboard-prev-lesson)
  (evil-local-set-key 'normal (kbd "q") #'lesson-dashboard-quit)
  (local-set-key (kbd "C-x C-s") #'lesson-dashboard-save)
  (local-set-key (kbd "C-s") #'lesson-dashboard-save)
  (add-hook 'post-command-hook #'lesson-dashboard--snap-cursor nil t)
  (add-hook 'after-change-functions #'lesson-dashboard--protect-tabs nil t)
  (add-hook 'kill-buffer-query-functions #'lesson-dashboard--kill-query nil t)
  (add-hook 'kill-buffer-hook #'lesson-dashboard--stop-timer nil t)
  (setq-local header-line-format nil))

;;;###autoload
(defun lesson-dashboard ()
  "Open the lesson dashboard for today's lessons."
  (interactive)
  (let ((lessons (lesson-dashboard--find-todays-lessons)))
    (if (null lessons)
        (message "No lessons scheduled for today.")
      (setq lesson-dashboard--lessons lessons)
      (setq lesson-dashboard--current-index 0)
      (switch-to-buffer (get-buffer-create lesson-dashboard-buffer-name))
      (lesson-dashboard-mode)
      (lesson-dashboard--refresh)
      (lesson-dashboard--start-timer)
      (message "C-h/C-l switch tabs, C-j/C-k next/prev lesson, C-x C-s save, q quit."))))

(provide '+lesson-dashboard)
