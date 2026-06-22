;;; init.el -*- lexical-binding: t; -*-

;; The literate config source lives in the org vault (it's an org-roam node);
;; it tangles to $DOOMDIR/config.el, which Doom loads as usual. Must be set
;; here so both `doom sync' and startup see it before the literate module runs.
(setq +literate-config-file
      (expand-file-name "~/org/roam/config/doom-config.org"))

(doom! :input

       :completion
       company
       (vertico +icons)

       :ui
       tabs
       doom              ; what makes DOOM look the way it does
       doom-dashboard    ; a nifty splash screen for Emacs
       doom-quit
       (emoji +unicode)
       minimap
       ligatures
       hl-todo           ; highlight TODO/FIXME/NOTE/DEPRECATED/HACK/REVIEW
       modeline          ; snazzy, Atom-inspired modeline, plus API
       nav-flash
       ophints           ; highlight the region an operation acts on
       (popup +defaults)   ; tame sudden yet inevitable temporary windows
       (vc-gutter +pretty) ; vcs diff in the fringe
       treemacs
       vi-tilde-fringe   ; fringe tildes to mark beyond EOB
       window-select
       workspaces        ; tab emulation, persistence & separate workspaces
       zen

       :editor
       (format +onsave)
       (evil +everywhere); come to the dark side, we have cookies
       file-templates    ; auto-snippets for empty files
       snippets          ; yasnippet support
       fold              ; (nigh) universal code folding
       (whitespace +guess +trim)  ; a butler for your whitespace
       word-wrap
       parinfer

       :emacs
       (dired +icons)             ; making dired pretty [functional]
       electric          ; smarter, keyword-based electric-indent
       ibuffer
       undo
       vc                ; version-control and Emacs, sitting in a tree

       :term

       :checkers
       syntax
       (spell +hunspell)
       grammar

       :tools
       (eval +overlay)     ; run code, run (also, repls)
       lookup              ; navigate your code and its documentation
       magit             ; a git porcelain for Emacs
       pdf

       :os
       (:if (featurep :system 'macos) macos)  ; improve compatibility with macOS

       :lang
       (org :dragndrop +roam +pomodoro +present +agenda +habits +pretty +pandoc +journal)
       emacs-lisp        ; drown in parentheses
       markdown          ; writing docs for people to ignore
       sh                ; she sells {ba,z,fi}sh shells on the C xor

       :email

       :app
       calendar

       :config
       (default +bindings +smartparens)
       literate)
