(setq org-directory "~/org/")

(use-package! savefold
  :init
  (setq savefold-backends '(org)
        savefold-directory (concat doom-cache-dir "savefold/"))
  :config
  (savefold-mode 1))

(after! org-modern
  (setq org-modern-checkbox nil)
  (setf (nth 2 org-modern-fold-stars) '("▶" . "▼"))
  (custom-set-faces!
    `(org-modern-tag :inherit org-modern-label :weight semibold :background ,(catppuccin-color 'mauve) :foreground ,(catppuccin-color 'mantle) :distant-foreground ,(catppuccin-color 'mauve))
    `(org-modern-done :inherit org-modern-label :weight semibold :background ,(catppuccin-color 'mantle) :foreground ,(catppuccin-color 'lavender))
    `(org-modern-progress-complete :background ,(catppuccin-color 'lavender) :foreground ,(catppuccin-color 'mantle))
    `(org-modern-progress-incomplete :background ,(catppuccin-color 'mantle) :foreground ,(catppuccin-color 'lavender))
    `(org-modern-date-active :background ,(catppuccin-color 'mantle) :foreground ,(catppuccin-color 'lavender))
    `(org-modern-time-active :background ,(catppuccin-color 'mantle) :foreground ,(catppuccin-color 'lavender))
    `(org-modern-date-inactive :background ,(catppuccin-color 'mantle) :foreground ,(catppuccin-color 'overlay0))
    `(org-modern-time-inactive :background ,(catppuccin-color 'mantle) :foreground ,(catppuccin-color 'overlay0))))

(after! org-appear
  (setq org-appear-autoemphasis t
        org-appear-autolinks t
        org-appear-autosubmarkers t))

(use-package! org-fragtog
  :when (require 'org-fragtog nil t)
  :hook (org-mode . org-fragtog-mode))

(after! ob-mermaid
  (setq ob-mermaid-cli-path (executable-find "mmdc")))

(after! org
  (add-to-list 'org-modules 'org-habit)
  (setq org-archive-location
        (concat (expand-file-name "archive/arch_%s" org-directory) "::"))
  (require 'ob-mermaid)
  (add-to-list 'org-babel-load-languages '(mermaid . t))
  (org-babel-do-load-languages 'org-babel-load-languages org-babel-load-languages)
  (setq org-use-property-inheritance
        (append (if (listp org-use-property-inheritance) org-use-property-inheritance nil)
                '("calendar-id" "CALENDAR-ID")))


  (defun my/org-gcal-post-all-in-buffer ()
    "Walk every heading with an active timestamp and call org-gcal-post-at-point.
Creates the :org-gcal: drawer so future org-gcal-sync-buffer calls pick them up."
    (interactive)
    (save-excursion
      (goto-char (point-min))
      (org-map-entries
       (lambda ()
         (let ((has-drawer
                (save-excursion
                  (org-back-to-heading t)
                  (let ((end (save-excursion (org-end-of-subtree t t))))
                    (re-search-forward "^[ \t]*:org-gcal:[ \t]*$" end t))))
               (has-ts
                (save-excursion
                  (org-back-to-heading t)
                  (let ((end (save-excursion (outline-next-heading) (point))))
                    (re-search-forward org-ts-regexp end t)))))
           (when (and has-ts (not has-drawer))
             (message "org-gcal: posting %s" (nth 4 (org-heading-components)))
             (org-gcal-post-at-point t nil)))))))
  (setq plstore-cache-passphrase-for-symmetric-encryption t
        plstore-encrypt-to '("yakovlievv25@gmail.com"))
  (require 'org-gcal)

  ;; Make org-gcal honor file-level #+PROPERTY: calendar-id ... and
  ;; inherited calendar-id properties so headings don't need their own.
  (defun my/org-gcal-inherit-calendar-id (orig-fn pom property &rest args)
    (let ((val (apply orig-fn pom property args)))
      (if (and (null val)
               (member property '("calendar-id" "CALENDAR-ID")))
          (or (apply orig-fn pom property t (cdr args))
              (cdr (assoc property org-file-properties)))
        val)))
  (advice-add 'org-entry-get :around #'my/org-gcal-inherit-calendar-id)
  (setq org-startup-with-latex-preview t)
  (setq org-log-done 'time
       org-hide-emphasis-markers t
        org-src-fontify-natively t
        org-agenda-show-inherited-tasks t
        org-habit-graph-column 50
        org-habit-preceding-days 30
        org-habit-following-days 10
        org-habit-show-habits-only-for-today nil
        org-agenda-sorting-strategy
        '((agenda time-up habit-down priority-down category-keep)
          (todo priority-down category-keep)
          (tags priority-down category-keep)
          (search category-keep))
        org-agenda-skip-scheduled-repeats-after-deadline t
        org-clock-persist 'history)
  (org-clock-persistence-insinuate))

(defun my/org-clock-in-when-doing ()
  "Clock in when the TODO state is switched to STRT."
  (when (string= org-state "STRT")
    (unless (org-clocking-p)
      (org-clock-in))))

(add-hook 'org-after-todo-state-change-hook #'my/org-clock-in-when-doing)

(defun my/parse-schedule (schedule-str)
  "Parse SCHEDULE-STR into an alist of (day-num . time-str).
Supports two formats:
  \"tue,thu 18:15-19:15\"           — shared time for all days
  \"tue 19:15-20:15, fri 16:00-17:00\" — per-day times"
  (let ((day-to-num (lambda (d)
                      (pcase (downcase (string-trim d))
                        ("sun" 0) ("mon" 1) ("tue" 2) ("wed" 3)
                        ("thu" 4) ("fri" 5) ("sat" 6)))))
    (if (string-match-p "," schedule-str)
        ;; Could be "tue,thu 18:15" or "tue 19:15, fri 16:00"
        ;; Distinguish: if first comma-segment has only a day name, it's shared-time
        (let* ((first-segment (string-trim (car (split-string schedule-str ","))))
               (first-parts (split-string first-segment)))
          (if (= 1 (length first-parts))
              ;; Shared time: "tue,thu 18:15-19:15"
              (let* ((parts (split-string (string-trim schedule-str)))
                     (days-str (car parts))
                     (time-str (cadr parts))
                     (day-names (split-string days-str ",")))
                (mapcar (lambda (d) (cons (funcall day-to-num d) time-str)) day-names))
            ;; Per-day: "tue 19:15-20:15, fri 16:00-17:00"
            (let ((segments (split-string schedule-str ",")))
              (mapcar (lambda (seg)
                        (let ((parts (split-string (string-trim seg))))
                          (cons (funcall day-to-num (car parts)) (cadr parts))))
                      segments))))
      ;; Single day: "wed 14:00-15:00"
      (let ((parts (split-string (string-trim schedule-str))))
        (list (cons (funcall day-to-num (car parts)) (cadr parts)))))))

(defun my/create-next-lesson ()
  "Create the next lesson heading based on #+SCHEDULE: in current buffer.
Refuses if :inactive: filetag is present."
  (interactive)
  (let ((filetags (or (car (cdr (assoc "FILETAGS" (org-collect-keywords '("FILETAGS"))))) "")))
    (when (string-match-p ":inactive:" filetags)
      (user-error "This student/group is marked as inactive")))
  (let* ((schedule-str (car (cdr (assoc "SCHEDULE" (org-collect-keywords '("SCHEDULE"))))))
         (_ (unless schedule-str (user-error "No #+SCHEDULE: found in this file")))
         (entries (my/parse-schedule schedule-str))
         (day-nums (mapcar #'car entries))
         (today-dow (nth 6 (decode-time)))
         (days-ahead (cl-loop for i from 0 to 6
                              for d = (mod (+ today-dow i) 7)
                              when (memq d day-nums)
                              return i))
         (next-dow (mod (+ today-dow days-ahead) 7))
         (time-str (cdr (assq next-dow entries)))
         (next-date (time-add (current-time) (days-to-time days-ahead)))
         (last-num (save-excursion
                     (goto-char (point-min))
                     (let ((max-n 0))
                       (while (re-search-forward "^\\* Lesson \\([0-9]+\\)" nil t)
                         (setq max-n (max max-n (string-to-number (match-string 1)))))
                       max-n)))
         (next-num (1+ last-num))
         (full-stamp (format-time-string
                      (concat "<%Y-%m-%d %a " time-str ">") next-date)))
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert (format "* Lesson %d %s\n" next-num full-stamp))
    (insert "** Pre-lesson\n")
    (insert (format "*** TODO prepare for lesson %d\n" next-num))
    (insert (format "DEADLINE: %s\n"
                    (format-time-string
                     (concat "<%Y-%m-%d %a "
                             (car (split-string time-str "-"))
                             ">")
                     next-date)))
    (insert "** Lesson\n")
    (insert "** Post-lesson\n")))

(defun my/auto-refresh-dashboard ()
  (when (and (buffer-file-name)
             (string= (file-name-nondirectory (buffer-file-name))
                      "20260311170322-dashboard.org"))
    (org-update-all-dblocks)))

(run-with-timer 0 60 #'my/auto-refresh-dashboard)

(defun org-dblock-write:notes-this-week (params)
  "Insert a list of org files created this week."
  (let* ((dir "~/org/")
         (week-start (org-read-date nil t "thisweek"))
         (files (directory-files dir t "\\.org$"))
         (results '()))
    (dolist (f files)
      (let ((creation-time (file-attribute-modification-time (file-attributes f))))
        (when (time-less-p week-start creation-time)
          (with-temp-buffer
            (insert-file-contents f nil 0 500)
            (let ((title (if (re-search-forward "^#\\+title:\\s-*\\(.*\\)" nil t)
                             (match-string 1)
                           (file-name-base f))))
              (push (cons title f) results))))))
    (if results
        (dolist (r (nreverse results))
          (insert (format "- [[file:%s][%s]]\n" (cdr r) (car r))))
      (insert "No new notes this week.\n"))))

(after! (evil org-agenda)
  (evil-define-text-object evil-org-agenda-a-day (count &optional beg end type)
    "Select the current day's content in org-agenda."
    :type line
    (when (derived-mode-p 'org-agenda-mode)
      (let (day-beg day-end)
        (save-excursion
          (beginning-of-line)
          (if (get-text-property (point) 'org-agenda-date-header)
              (setq day-beg (line-beginning-position))
            (let ((pos (previous-single-property-change (point) 'org-agenda-date-header)))
              (when pos
                (setq day-beg (save-excursion
                                (goto-char pos)
                                (if (get-text-property (point) 'org-agenda-date-header)
                                    (line-beginning-position)
                                  (goto-char (previous-single-property-change (point) 'org-agenda-date-header))
                                  (line-beginning-position))))))))
        (save-excursion
          (goto-char (or day-beg (point)))
          (forward-line 1)
          (let ((pos (next-single-property-change (point) 'org-agenda-date-header)))
            (setq day-end (if pos
                              (save-excursion
                                (goto-char pos)
                                (if (get-text-property (point) 'org-agenda-date-header)
                                    (line-beginning-position)
                                  (line-beginning-position)))
                            (point-max)))))
        (when (and day-beg day-end)
          (evil-range day-beg day-end 'line)))))

  (evil-define-key 'operator org-agenda-mode-map "ad" #'evil-org-agenda-a-day)
  (evil-define-key 'visual org-agenda-mode-map "ad" #'evil-org-agenda-a-day))
