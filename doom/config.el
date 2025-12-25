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
          '(
            ("d" "default" entry "%?"
             :target (file+head
                       "%<%Y-%m-%d>.org"
                       "#+title: %<%Y-%m-%d>\n#+filetags: %<:%Y:%B:>\n\n* Morning log\n:PROPERTIES:\n:WAKE_UP:\n:BED_TIME:\n:MOOD:\n:END:\n\n* The lore\n\n* Focus blocks\n\n"))
            ("f" "Focus Block" entry
             "* %^{Title}\n:PROPERTIES: \n:START: %^{Start time}T\n:END_TIME: %^{End time}T\n:DURATION: %^{Duration}\n:END:\n"
             :target (file+olp "%<%Y-%m-%d>.org" ("Focus blocks")))
            )
          )
        )

(map! :leader
      :desc "Open today's daily note"
      "d d" #'org-roam-dailies-goto-today
      :desc "Capture into daily note"
      "d f" #'org-roam-dailies-capture-today)
