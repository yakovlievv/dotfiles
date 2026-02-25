(setq org-directory "~/org/")

(after! org
  (add-to-list 'org-modules 'org-habit)
  (setq org-archive-location
        (expand-file-name "archive/arch-%s:"
                          org-directory))
  (setq org-log-done 'time
        org-hide-emphasis-markers t
        org-src-fontify-natively t
        org-agenda-show-inherited-tasks t
        org-habit-graph-column 50
        org-habit-preceding-days 30
        org-habit-following-days 10
        org-habit-show-habits-only-for-today nil
        org-agenda-skip-scheduled-repeats-after-deadline t
        org-clock-persist 'history)
  (org-clock-persistence-insinuate))

(defun my/org-clock-in-when-doing ()
  "Clock in when the TODO state is switched to STRT."
  (when (string= org-state "STRT")
    (unless (org-clocking-p)
      (org-clock-in))))

(add-hook 'org-after-todo-state-change-hook #'my/org-clock-in-when-doing)

(defun my/org-auto-commit ()
  (let ((default-directory "~/org/"))
    (when (and (file-directory-p default-directory)
               (file-directory-p (concat default-directory ".git")))
      (when (not (string-empty-p
                  (shell-command-to-string "git status --porcelain")))
        ;; Commit
        (shell-command "git add -A")
        (shell-command
         (format "git commit -m 'Auto commit: %s'"
                 (format-time-string "%Y-%m-%d %H:%M")))
        ;; Push asynchronously
        (start-process "org-auto-push" nil "git" "push")))))

(run-with-timer
 (* 4 60 60)
 (* 4 60 60)
 #'my/org-auto-commit)
