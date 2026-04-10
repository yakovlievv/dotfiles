;;; +keybinds.el -*- lexical-binding: t; -*-

(defun my/evil-next-line (count)
  "Move by visual lines without count, logical lines with count."
  (interactive "p")
  (if (> count 1)
      (evil-next-line count)
    (evil-next-visual-line 1)))

(defun my/evil-previous-line (count)
  "Move by visual lines without count, logical lines with count."
  (interactive "p")
  (if (> count 1)
      (evil-previous-line count)
    (evil-previous-visual-line 1)))

(map! :nv "j" #'my/evil-next-line
      :nv "k" #'my/evil-previous-line)

(global-unset-key (kbd "C-s"))
(map! "C-s" #'save-buffer)
(map! "C-q" #'save-buffers-kill-terminal)

(after! org
  (map! :map org-mode-map
        :n "C-a" #'evil-numbers/inc-at-pt
        :n "C-x" #'evil-numbers/dec-at-pt
        :v "g C-a" #'evil-numbers/inc-at-pt-in-visual
        :v "g C-x" #'evil-numbers/dec-at-pt-in-visual))

(map! :leader
      :desc "Writing hub" "n w" #'writing-hub
      :desc "Lesson dashboard" "n l" #'lesson-dashboard)

(defvar org-link-vsplit-window nil
  "Window reused for link preview.")

(defvar my/link-preview-mode nil
  "Non-nil when live link preview is active.")

(defvar my/link-preview-last-target nil
  "Last previewed target, to avoid redundant updates.")

(defun my/ensure-vsplit-window ()
  "Ensure the vsplit preview window exists and return it."
  (if (and org-link-vsplit-window
           (window-live-p org-link-vsplit-window))
      org-link-vsplit-window
    (let ((win (split-window-right)))
      (setq org-link-vsplit-window win)
      win)))

(defun my/preview-file-in-vsplit (file)
  "Show FILE in the vsplit preview window."
  (let ((win (my/ensure-vsplit-window)))
    (with-selected-window win
      (find-file file))))

(defun my/org-link-target-at-point ()
  "Return the file path of the org link at point, or nil."
  (let ((ctx (org-element-context)))
    (when (eq (org-element-type ctx) 'link)
      (let ((type (org-element-property :type ctx))
            (path (org-element-property :path ctx)))
        (cond
         ((string= type "file") (expand-file-name path))
         ((string= type "id")
          (when-let ((loc (org-id-find path)))
            (car loc)))
         (t nil))))))

(defun my/link-preview-post-command ()
  "Preview the org link under cursor in the vsplit window."
  (when my/link-preview-mode
    (let ((target (my/org-link-target-at-point)))
      (cond
       ((and target (not (equal target my/link-preview-last-target))
             (file-exists-p target))
        (setq my/link-preview-last-target target)
        (my/preview-file-in-vsplit target))
       ((and (null target) my/link-preview-last-target)
        nil)))))

(defun my/link-preview-cleanup ()
  "Clean up preview state when the vsplit window is closed."
  (unless (and org-link-vsplit-window
               (window-live-p org-link-vsplit-window))
    (setq my/link-preview-mode nil
          my/link-preview-last-target nil)
    (remove-hook 'post-command-hook #'my/link-preview-post-command t)))

(defun org-open-link-in-vsplit ()
  "Toggle live link preview in a vertical split.
When enabled, moving the cursor over org links automatically
previews the linked file. Press again to close."
  (interactive)
  (if my/link-preview-mode
      (progn
        (setq my/link-preview-mode nil
              my/link-preview-last-target nil)
        (remove-hook 'post-command-hook #'my/link-preview-post-command t)
        (remove-hook 'window-configuration-change-hook #'my/link-preview-cleanup t)
        (when (and org-link-vsplit-window (window-live-p org-link-vsplit-window))
          (delete-window org-link-vsplit-window))
        (setq org-link-vsplit-window nil)
        (message "Link preview off"))
    (setq my/link-preview-mode t
          my/link-preview-last-target nil)
    (add-hook 'post-command-hook #'my/link-preview-post-command nil t)
    (add-hook 'window-configuration-change-hook #'my/link-preview-cleanup nil t)
    (my/link-preview-post-command)
    (message "Link preview on")))

(defvar my/material-preview-timer nil
  "Timer for debounced material preview.")

(defvar my/material-preview-last nil
  "Last previewed material candidate.")

(defun my/material-preview-candidate (rel-alist)
  "Preview the current vertico candidate in the vsplit window."
  (when-let* ((cand (and (bound-and-true-p vertico--candidates)
                         (nth vertico--index vertico--candidates)))
              ((not (equal cand my/material-preview-last)))
              (abs-path (alist-get cand rel-alist nil nil #'equal))
              ((file-exists-p abs-path)))
    (setq my/material-preview-last cand)
    (my/preview-file-in-vsplit abs-path)))

(defun my/org-insert-material-links ()
  "Pick material files and insert as org links.
TAB marks/unmarks files. Preview shown in vsplit as you navigate."
  (interactive)
  (let* ((dir (expand-file-name "material/" org-directory))
         (files (directory-files-recursively dir ""))
         (rel-alist (mapcar (lambda (f)
                              (cons (file-relative-name f dir) f))
                            files))
         (candidates (mapcar #'car rel-alist))
         (selected '())
         (keymap (make-sparse-keymap)))
    (unless candidates
      (user-error "No files in %s" dir))
    (define-key keymap [tab]
      (lambda ()
        (interactive)
        (let ((cand (nth vertico--index vertico--candidates)))
          (when cand
            (if (member cand selected)
                (setq selected (delete cand selected))
              (push cand selected))
            (vertico--exhibit)))))
    (setq my/material-preview-last nil)
    (my/ensure-vsplit-window)
    (minibuffer-with-setup-hook
        (lambda ()
          (use-local-map (make-composed-keymap keymap (current-local-map)))
          (add-hook 'post-command-hook
                    (lambda ()
                      (when my/material-preview-timer
                        (cancel-timer my/material-preview-timer))
                      (setq my/material-preview-timer
                            (run-with-idle-timer
                             0.05 nil
                             #'my/material-preview-candidate rel-alist)))
                    nil t))
      (let ((chosen (completing-read
                      "Material (TAB mark, RET confirm): "
                      (lambda (str pred action)
                        (if (eq action 'metadata)
                            (list 'metadata
                                  (cons 'annotation-function
                                        (lambda (cand)
                                          (if (member cand selected) " [x]" ""))))
                          (complete-with-action action candidates str pred))))))
        (unless (member chosen selected)
          (push chosen selected))))
    (when my/material-preview-timer
      (cancel-timer my/material-preview-timer)
      (setq my/material-preview-timer nil))
    (when (and org-link-vsplit-window (window-live-p org-link-vsplit-window))
      (delete-window org-link-vsplit-window)
      (setq org-link-vsplit-window nil))
    (when selected
      (dolist (rel (nreverse selected))
        (insert (format "[[file:%s]]\n"
                        (alist-get rel rel-alist nil nil #'equal)))))))

(after! org
  (map! :map org-mode-map
        :localleader
        :desc "Link material" "l m" #'my/org-insert-material-links
        :desc "Open link in vsplit" "l v" #'org-open-link-in-vsplit))

(after! image-mode
  (map! :map image-mode-map
        :n "RET" (cmd! (call-process "open" nil 0 nil (buffer-file-name)))))

