(after! org-roam
  (require 'org-roam-dailies)
  (setq
   book-gallery-weekly-goal-minutes 180
   org-roam-directory "~/org/roam/"
   org-roam-dailies-directory "daily/"
   org-roam-dailies-capture-templates
   '(("d" "default" entry "%?"
      :target (file+head
               "%<%Y-%m-%d>.org"
               ":PROPERTIES:\n:ID:       %(org-id-new)\n:SLEEP_TIME: %^T--%^T\n:END:\n#+title: %<%Y-%m-%d>\n#+filetags: :daily:\n\n")))
   org-roam-capture-templates
   '(("d" "default" plain "%?"
      :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                          "#+title: ${title}\n")
      :unnarrowed t))
   org-agenda-files
   (append
    (list org-roam-directory)
    (list "~/org/archive")))
  (defvar +org-roam-book-capture-template
    '("b" "book" plain "%?"
      :target (file+head
               "%<%Y%m%d%H%M%S>-${slug}.org"
               ":PROPERTIES:\n:ID:       %(org-id-new)\n:AUTHOR:   %^{Author}\n:COVER:    [[%^{Cover URL}]]\n:RATING:   0\n:PAGES_READ: 0\n:TOTAL_PAGES: %^{Total pages}\n:END:\n#+title: ${title}\n#+filetags: :book:planned:\n\n* Read log\n:LOGBOOK:\n:END:\n")
      :unnarrowed t)
    "Org-roam capture template for books.")
  (org-roam-db-autosync-mode))
