(global-unset-key (kbd "C-s"))
(map! "C-s" #'save-buffer)
(map! "C-q" #'save-buffers-kill-terminal)

(after! org
  (map! :map org-mode-map
        :n "C-a" #'evil-numbers/inc-at-pt
        :n "C-x" #'evil-numbers/dec-at-pt
        :v "g C-a" #'evil-numbers/inc-at-pt-in-visual
        :v "g C-x" #'evil-numbers/dec-at-pt-in-visual))

(map! :leader
      :desc "Writing hub" "n w" #'writing-hub
      :desc "Lesson dashboard" "n l" #'lesson-dashboard)

(defvar org-link-vsplit-window nil
  "Window reused by `org-open-link-in-vsplit'.")

(defun org-open-link-in-vsplit ()
  "Open org link at point in a vertical split, reusing the same window.
Cursor stays in the original window."
  (interactive)
  (let ((orig-window (selected-window))
        (org-link-frame-setup
         (cons `(file . ,(lambda (f)
                           (if (and org-link-vsplit-window
                                    (window-live-p org-link-vsplit-window))
                               (progn
                                 (select-window org-link-vsplit-window)
                                 (find-file f))
                             (let ((win (split-window-right)))
                               (setq org-link-vsplit-window win)
                               (select-window win)
                               (find-file f)))))
               org-link-frame-setup)))
    (org-open-at-point)
    (select-window orig-window)))

(after! org
  (map! :map org-mode-map
        :localleader
        :desc "Link material" "l m"
        (cmd!
         (let* ((dir (expand-file-name "material/" org-directory))
                (file (read-file-name "Material: " dir)))
           (insert (format "[[file:%s]]" file))))
        :desc "Open link in vsplit" "l v" #'org-open-link-in-vsplit))

(after! image-mode
  (map! :map image-mode-map
        :n "RET" (cmd! (call-process "open" nil 0 nil (buffer-file-name)))))

