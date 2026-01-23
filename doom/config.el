(setq org-directory "~/Documents/org/")
(setq doom-theme 'catppuccin)
;; Set default font and size
;; Monospaced Nerd Font
(setq doom-font (font-spec :family "JetBrainsMono Nerd Font Mono" :size 16))


;; Optional: fallback for variable-pitch
(setq doom-variable-pitch-font (font-spec :family "JetBrainsMono Nerd Font" :size 16))

(defun my/print-frame-size ()
  "Print the current frame's width, height, left, and top."
  (interactive)
  (message "width: %s, height: %s, left: %s, top: %s"
           (frame-parameter nil 'width)
           (frame-parameter nil 'height)
           (frame-parameter nil 'left)
           (frame-parameter nil 'top)))


;; Set default Emacs window size on launch
(setq initial-frame-alist
      '((width . 127)     ;; characters wide
        (height . 36)     ;; lines tall
        (left . 72)       ;; pixels from left of screen
        (top . 79)))      ;; pixels from top of screen

;; Optional: also resize new frames opened later
(setq default-frame-alist initial-frame-alist)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

;; Make sure exec-path-from-shell is loaded first
(use-package! exec-path-from-shell
              :config
              (when (memq window-system '(mac ns x))
                (exec-path-from-shell-initialize)))

(after! org
        (add-to-list 'org-modules 'org-habit)

        (setq org-log-done 'time
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

(defun my/org-auto-commit ()
  (let ((default-directory "~/Documents/org/"))  ; Fixed path
    (when (and (file-directory-p default-directory)
               (file-directory-p (concat default-directory ".git")))
      (when (not (string-empty-p
                   (shell-command-to-string "git status --porcelain")))
        ;; Commit
        (shell-command "git add -A")
        (shell-command
          (format "git commit -m 'Auto commit: %s'"
                  (format-time-string "%Y-%m-%d %H:%M")))
        ;; Push asynchronously
        (start-process "org-auto-push" nil "git" "push")))))

(run-with-timer
  (* 2 60 60)   ;; 2 hours in seconds
  (* 2 60 60)
  #'my/org-auto-commit)

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
             ":PROPERTIES:\n:BED_TIME: %^T\n:WAKE_TIME: %^T\n:END:\n\n"
             :target (file+olp "%<%Y-%m-%d>.org" ("Morning log")))
            ("t" "Daily task" entry
             "* %^{Title}\n:PROPERTIES:\n:PLANNED:%^T\n:DEADLINE: %^T\n:END:"
             :target (file+olp "%<%Y-%m-%d>.org" ("Tasks")))
            )
          )
        )
