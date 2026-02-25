(setq org-directory "~/org/")
(setq doom-theme 'catppuccin)
;; Set default font and sizo
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
  (setq org-archive-location
        (expand-file-name "archive/arch-%s:"
                          org-directory))
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

(defun my/org-clock-in-when-doing ()
  "Clock in when the TODO state is switched to STRT."
  (when (string= org-state "STRT")
    (unless (org-clocking-p)
      (org-clock-in))))

(add-hook 'org-after-todo-state-change-hook #'my/org-clock-in-when-doing)

(defun my/org-auto-commit ()
  (let ((default-directory "~/org/"))
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
 (* 4 60 60)
 (* 4 60 60)
 #'my/org-auto-commit)

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

(global-unset-key (kbd "C-s"))
(map! "C-s" #'save-buffer)
(map! "C-q" #'save-buffers-kill-terminal)

(after! org
  (map! :map org-mode-map
        :n "C-a" #'evil-numbers/inc-at-pt
        :n "C-x" #'evil-numbers/dec-at-pt
        :v "g C-a" #'evil-numbers/inc-at-pt-in-visual
        :v "g C-x" #'evil-numbers/dec-at-pt-in-visual))
