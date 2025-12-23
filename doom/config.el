(setq org-directory "~/Documents/org/")
(setq doom-theme 'catppuccin)
(after! org
        (setq org-log-done 'time))

(defun my/add-focus-session ()
  "Add a focus session to today's daily note under Focus blocks."
  (interactive)
  (let* ((title (read-string "Focus session title: "))
         (daily-file (expand-file-name 
                      (format-time-string "%Y-%m-%d.org")
                      (concat org-roam-directory org-roam-dailies-directory)))
         (time-stamp (format-time-string "[%Y-%m-%d %a %H:%M]")))
    
    ;; Create daily note if it doesn't exist
    (unless (file-exists-p daily-file)
      (org-roam-dailies-goto-today))
    
    ;; Open the daily file
    (find-file daily-file)
    
    ;; Find Focus blocks heading
    (goto-char (point-min))
    (if (re-search-forward "^\\* Focus blocks" nil t)
        (progn
          (org-end-of-subtree)
          (insert (format "\n** %s\n:PROPERTIES:\n:START: %s\n:END:\n:NOTES:\n:END:\n" 
                          title time-stamp))
          (forward-line -2))
      (message "Could not find Focus blocks heading!"))))

(after! org-roam
        (org-roam-db-autosync-mode)
        (require 'org-roam-dailies)
        (setq
          org-roam-directory "~/Documents/org/roam/"
          org-roam-dailies-directory "daily/"
          org-roam-dailies-capture-templates
          '(
            ("d" "default" entry "* %?"
             :if-new (file+head
                       "%<%Y-%m-%d>.org"
                       "#+title: %<%Y-%m-%d>\n#+filetags: %<:%Y:%B:>\n\n* Morning log\n:PROPERTIES:\n:WAKE_UP:\n:BED_TIME:\n:MOOD:\n:END:\n\n* The lore\n\n* Focus blocks\n\n")
             )
            )
          )
        )

(map! :leader
      :desc "Open today's daily note"
      "d d" #'org-roam-dailies-goto-today
      :desc "Add focus session"
      "d f" #'my/add-focus-session)
