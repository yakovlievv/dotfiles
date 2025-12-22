(setq org-directory "~/Documents/org/")

(after! org
        (setq org-log-done 'time))

(after! org-roam
        (org-roam-db-autosync-mode)
        (require 'org-roam-dailies)

        (setq
          org-roam-directory "~/Documents/org/roam/"
          org-roam-dailies-directory "daily/"
          org-roam-dailies-capture-templates
          '(("d" "default" entry
             "* %?"
             :if-new (file+head
                       "%<%Y-%m-%d>.org"
                       "\n#+title: %<%Y-%m-%d>\n #+filetags: %<:%Y:%B:>\n\n* Journal\n\n* Tasks\n\n"
                       )
             )
            )
          )
        )


(map! :leader
      :desc "Open today's daily note"
      "d d" #'org-roam-dailies-goto-today)
