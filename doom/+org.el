(setq org-directory "~/org/")

(use-package! savefold
  :init
  (setq savefold-backends '(org)
        savefold-directory (concat doom-cache-dir "savefold/"))
  :config
  (savefold-mode 1))

(after! org
  (add-to-list 'org-modules 'org-habit)
  (setq org-archive-location
        (concat (expand-file-name "archive/arch_%s" org-directory) "::"))
  (setq org-log-done 'time
        org-image-actual-width 300
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
