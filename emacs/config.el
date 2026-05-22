;;; -*- lexical-binding: t -*-

(setq doom-theme 'catppuccin)
(setq doom-font (font-spec :family "JetBrainsMono Nerd Font Mono" :size 16))

;; Optional: fallback for variable-pitch
(setq doom-variable-pitch-font (font-spec :family "JetBrainsMono Nerd Font" :size 16))

;; config.el
(after! dirvish
  (dirvish-override-dired-mode)  ; replace dired with dirvish everywhere
  (setq dirvish-preview-dispatchers
        (append dirvish-preview-dispatchers '(image)))  ; enable image preview
  (setq dirvish-quick-access-entries
        '(("o" "~/org/"          "Org vault")
          ("r" "~/org/roam/"     "Roam notes")
          ("m" "~/org/material/" "Material")))
  (setq dirvish-attributes '(nerd-icons)))

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
(setq display-line-numbers-type 'visual)
(global-display-line-numbers-mode 1)

;; Make sure exec-path-from-shell is loaded first
(use-package! exec-path-from-shell
  :config
  (when (memq window-system '(mac ns x))
    (exec-path-from-shell-initialize)))

(setq ispell-program-name "aspell"
      ispell-dictionary "en"
      ispell-extra-args '("--sug-mode=ultra" "--encoding=utf-8"))

(defun my/ispell-set-personal-dict (&rest _)
  "Switch personal dictionary to match the current ispell dictionary."
  (setq ispell-personal-dictionary
        (expand-file-name (format "ispell/%s.pws"
                                  (or (bound-and-true-p ispell-current-dictionary)
                                      (bound-and-true-p ispell-dictionary)
                                      "en"))
                          doom-data-dir)))

(after! ispell
  (my/ispell-set-personal-dict)
  (advice-add 'ispell-change-dictionary :after #'my/ispell-set-personal-dict)
  (advice-add 'ispell-internal-change-dictionary :after #'my/ispell-set-personal-dict))

(use-package! guess-language
  :hook ((text-mode . guess-language-mode)
         (org-mode  . guess-language-mode))
  :config
  (setq guess-language-languages '(en ru uk)
        guess-language-min-paragraph-length 10
        guess-language-langcodes
        '((en . ("en"   "English"))
          (ru . ("ru"   "Russian"))
          (uk . ("uk"   "Ukrainian")))))

(defun my/spell-set-dict (dict)
  "Set the ispell dictionary used for `z=' / `ispell-word' suggestions."
  (interactive
   (list (completing-read "Dictionary: " '("en" "ru" "uk" "ru-yo"))))
  (ispell-change-dictionary dict)
  (message "Spell dictionary: %s" dict))

(after! spell-fu
  (let ((pws (lambda (name)
               (spell-fu-get-personal-dictionary
                name (expand-file-name (format "ispell/%s.pws" name)
                                       doom-data-dir)))))
    (setq-default spell-fu-dictionaries
                  (list (spell-fu-get-ispell-dictionary "en")
                        (spell-fu-get-ispell-dictionary "ru")
                        (spell-fu-get-ispell-dictionary "uk")
                        (funcall pws "en")
                        (funcall pws "ru")
                        (funcall pws "uk")))))

(after! langtool
  (setq langtool-bin "languagetool"
        langtool-default-language "en-US"
        langtool-disabled-rules '("MORFOLOGIK_RULE_EN_US"
                                  "UPPERCASE_SENTENCE_START"
                                  "COMMA_PARENTHESIS_WHITESPACE"
                                  "EN_QUOTES")))

(after! writegood-mode
  (dolist (hook '(org-mode-hook
                  markdown-mode-hook
                  rst-mode-hook
                  asciidoc-mode-hook
                  latex-mode-hook
                  LaTeX-mode-hook))
    (remove-hook hook #'writegood-mode)))

(map! :leader
      :prefix ("l" . "language")
      :desc "Check grammar"    "g" #'langtool-check
      :desc "Done checking"    "G" #'langtool-check-done
      :desc "Show message"     "m" #'langtool-show-message-at-point
      :desc "Correct buffer"   "c" #'langtool-correct-buffer
      :desc "Set spell dict"   "d" #'my/spell-set-dict)

(after! org-modern
  (setq org-modern-table t))

(load! "+org")
(load! "+org-roam")
(load! "+book-gallery")
(load! "+writing-hub")
(load! "+keybinds")
(load! "+lesson-dashboard")
