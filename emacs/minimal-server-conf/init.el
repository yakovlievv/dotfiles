;; i use this config on a server. i don't need to be loading the full doom
;; emacs monstorcity on my server, i just need a minimal config that will run
;; the simple things.


(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(unless package-archive-contents (package-refresh-contents))

(dolist (pkg '(org-roam websocket org-roam-ui))
  (unless (package-installed-p pkg)
    (package-install pkg)))

(require 'org-roam)
(require 'org-roam-ui)

(setq org-roam-directory "/home/liev/org/roam")

(org-roam-db-autosync-mode 1)

(org-roam-ui-mode 1)
(custom-set-variables
 '(package-selected-packages nil))
(custom-set-faces)
