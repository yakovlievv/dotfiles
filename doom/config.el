(setq org-directory "~/Documents/org/")
(setq doom-theme 'catppuccin)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

(after! org
        ;; (require 'org-ql)
        (setq org-log-done 'time)
        (setq org-hide-emphasis-markers t)
        (setq org-src-fontify-natively t)
        (setq org-agenda-show-inherited-tasks t)
        (setq org-clock-persist t))


(org-clock-persistence-insinuate)

(defun my/org-auto-commit ()
  (let ((default-directory "~/Documents/org/"))  ; Fixed path
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
 (* 2 60 60)   ;; 2 hours in seconds
 (* 2 60 60)
 #'my/org-auto-commit)

(after! org-roam
        (org-roam-db-autosync-mode)
        (require 'org-roam-dailies)
        (setq
          org-roam-directory "~/Documents/org/roam/"
          org-roam-dailies-directory "daily/"
          org-roam-dailies-capture-templates
          '(
            ("d" "default" entry "%?"
             :target (file+head
                       "%<%Y-%m-%d>.org"
                       "#+title: %<%Y-%m-%d>\n#+filetags: %<:%Y:%B:>\n\n* Morning log\n\n* The lore\n\n* Tasks\n\n* Focus blocks\n\n")
             )
            ("f" "Focus Block" entry
             "* %^{Title}\n:PROPERTIES:\n:END:\n"
             :target (file+olp "%<%Y-%m-%d>.org" ("Focus blocks")))
            ("m" "Morning Log" plain
             ":PROPERTIES:\n:BED_TIME: %^T\n:WAKE_TIME: %^T\n:END:\n\n"
             :target (file+olp "%<%Y-%m-%d>.org" ("Morning log")))
            ("t" "Daily task" entry
             "* %^{Title}\n:PROPERTIES:\n:PLANNED:%^T\n:DEADLINE: %^T\n:END:"
             :target (file+olp "%<%Y-%m-%d>.org" ("Tasks")))
            )
          )
        )


