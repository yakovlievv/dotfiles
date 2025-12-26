(setq org-directory "~/Documents/org/")
(setq doom-theme 'catppuccin)

(after! org
        (setq org-log-done 'time)
        (setq org-hide-emphasis-markers t)
        (setq org-clock-persist t))

(org-clock-persistence-insinuate)

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
             ":PROPERTIES:\n:BED_TIME: %^T\n:WAKE_TIME: %^T\n:END:"
             :target (file+olp "%<%Y-%m-%d>.org" ("Morning log")))
            )
          )
        )

(map! :leader
      :desc "Open today's daily note"
      "d d" #'org-roam-dailies-goto-today
      :desc "Capture into daily note"
      "d f" #'org-roam-dailies-capture-today)
