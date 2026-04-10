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
