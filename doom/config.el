(setq org-directory "~/Documents/org/")
(setq doom-theme 'catppuccin)

(after! org
        (setq org-log-done 'time))

(after! org-roam
        (org-roam-db-autosync-mode)
        (require 'org-roam-dailies)

        (setq
          org-roam-directory "~/Documents/org/roam/"
          org-roam-dailies-directory "daily/"
          org-roam-dailies-capture-templates
          '(("d" "default" entry "* %?"
             :if-new (file+head
                       "%<%Y-%m-%d>.org"
                       "\n#+title: %<%Y-%m-%d>\n#+filetags: %<:%Y:%B:>\n\n* Morning log\n:PROPERTIES:\n:WAKE_UP:\n:BED_TIME:\n:MOOD:\n:END:\n\n* The lore\n\n* Focus blocks\n\n")))))

(map! :leader
      :desc "Open today's daily note"
      "d d" #'org-roam-dailies-goto-today)
