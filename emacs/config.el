(setq doom-theme 'catppuccin)
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

(setq ispell-dictionary "en"
      ispell-personal-dictionary
      (expand-file-name "ispell/en.pws" doom-data-dir))

(after! langtool
  (setq langtool-bin "languagetool"
        langtool-default-language "en-US"
        langtool-disabled-rules '("MORFOLOGIK_RULE_EN_US"
                                  "UPPERCASE_SENTENCE_START"
                                  "COMMA_PARENTHESIS_WHITESPACE"
                                  "EN_QUOTES")))

(map! :leader
      :prefix ("l" . "language")
      :desc "Check grammar"    "g" #'langtool-check
      :desc "Done checking"    "G" #'langtool-check-done
      :desc "Show message"     "m" #'langtool-show-message-at-point
      :desc "Correct buffer"   "c" #'langtool-correct-buffer)

(load! "+org")
(load! "+org-roam")
(load! "+book-gallery")
(load! "+writing-hub")
(load! "+keybinds")
(load! "+lesson-dashboard")
