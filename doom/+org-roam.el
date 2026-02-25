(after! org-roam
  (org-roam-db-autosync-mode)
  (require 'org-roam-dailies)
  (setq
   org-roam-directory "~/org/"
   org-roam-dailies-directory "daily/"
   org-roam-dailies-capture-templates
   '(("d" "default" entry "%?"
      :target (file+head
               "%<%Y-%m-%d>.org"
               ":PROPERTIES:\n:ID:       %(org-id-new)\n:SLEEP_TIME: %^T--%^T\n:END:\n#+title: %<%Y-%m-%d>\n#+filetags: %<:%Y:%B:>\n\n")))
   org-agenda-files
   (append
    (list org-roam-directory)
    (list "~/org/archive"))))
