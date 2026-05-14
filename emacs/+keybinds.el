;;; +keybinds.el -*- lexical-binding: t; -*-

(evil-define-motion my/evil-next-line (count)
  "Move by visual lines without count, logical lines with count."
  :type line
  (if (and count (> count 1))
      (evil-next-line count)
    (evil-next-visual-line 1)))

(evil-define-motion my/evil-previous-line (count)
  "Move by visual lines without count, logical lines with count."
  :type line
  (if (and count (> count 1))
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

(defun my/fit-window-to-image ()
  "When the current buffer shows an image, resize the window to its rendered width."
  (when (and (derived-mode-p 'image-mode)
             (image-get-display-property)
             (not (one-window-p)))
    (redisplay t)
    (let* ((img-w-px (car (image-display-size
                           (image-get-display-property) t)))
           (pad-px (* 2 (frame-char-width)))
           (target-px (+ img-w-px pad-px))
           (delta-px (- target-px (window-body-width nil t))))
      (when (/= 0 delta-px)
        (ignore-errors
          (window-resize nil delta-px t nil t))))))

(defun my/preview-file-in-vsplit (file)
  "Show FILE in the vsplit preview window."
  (let ((win (my/ensure-vsplit-window)))
    (with-selected-window win
      (find-file file)
      (display-line-numbers-mode -1)
      (my/fit-window-to-image))))

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
    (my/kill-image-buffers)
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

(defun my/kill-image-buffers ()
  "Kill every buffer in `image-mode' so previews re-render fresh."
  (dolist (buf (buffer-list))
    (when (with-current-buffer buf (derived-mode-p 'image-mode))
      (kill-buffer buf))))

(defun my/org-insert-material-links ()
  "Pick material files and insert as org links.
TAB marks/unmarks files. Preview shown in vsplit as you navigate.
Searches `material/' recursively, so files organized into topic
subfolders are included; candidates show the relative path."
  (interactive)
  (let* ((dir (expand-file-name "material/" org-directory))
         (files (directory-files-recursively
                 dir "\\`[^.]" nil
                 (lambda (sub)
                   (not (string-prefix-p
                         "." (file-name-nondirectory
                              (directory-file-name sub)))))))
         (rel-alist (mapcar (lambda (f)
                              (cons (file-relative-name f dir) f))
                            files))
         (candidates (sort (mapcar #'car rel-alist) #'string<))
         (selected '())
         (keymap (make-sparse-keymap)))
    (unless candidates
      (user-error "No files in %s" dir))
    (my/kill-image-buffers)
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

(defvar my/external-links-file
  (expand-file-name "external-links.org" "~/org/roam/")
  "Path to the centralized external links file.")

(defun my/org-external-links--parse ()
  "Return an alist of (description . url) parsed from the external links file."
  (let ((file my/external-links-file)
        (results '()))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward
                "\\[\\[\\(https?://[^]]+\\)\\]\\[\\([^]]+\\)\\]\\]"
                nil t)
          (push (cons (match-string-no-properties 2)
                      (match-string-no-properties 1))
                results))))
    (nreverse results)))

(defun my/org-insert-external-link ()
  "Pick an external link from the central file and insert it at point."
  (interactive)
  (let* ((alist (my/org-external-links--parse))
         (_ (unless alist
              (user-error "No links found in %s" my/external-links-file)))
         (choice (completing-read "External link: " (mapcar #'car alist) nil t))
         (url (alist-get choice alist nil nil #'equal)))
    (insert (format "[[%s][%s]]" url choice))))

(defun my/migrate-external-links-to-central ()
  "One-shot: harvest external http(s) links from :tutoring:material: org-roam
files into `my/external-links-file', grouped by source file title.
Refuses to overwrite an existing non-trivial file."
  (interactive)
  (let ((target my/external-links-file)
        (sources '())
        (count 0))
    (when (and (file-exists-p target)
               (> (or (file-attribute-size (file-attributes target)) 0) 200))
      (unless (yes-or-no-p (format "%s already has content. Overwrite? " target))
        (user-error "Aborted")))
    (dolist (f (directory-files-recursively "~/org/roam/" "\\.org$"))
      (unless (string= (expand-file-name f) (expand-file-name target))
        (with-temp-buffer
          (insert-file-contents f)
          (goto-char (point-min))
          (when (re-search-forward "^#\\+filetags:.*:material:" nil t)
            (goto-char (point-min))
            (let ((title (when (re-search-forward
                                "^#\\+title:\\s-*\\(.*\\)" nil t)
                           (string-trim (match-string-no-properties 1))))
                  (links '()))
              (goto-char (point-min))
              (while (re-search-forward
                      "\\[\\[\\(https?://[^]]+\\)\\(?:\\]\\[\\([^]]+\\)\\)?\\]\\]"
                      nil t)
                (push (cons (match-string-no-properties 1)
                            (match-string-no-properties 2))
                      links))
              (when (and title links)
                (push (cons title (nreverse links)) sources)))))))
    (with-temp-buffer
      (insert ":PROPERTIES:\n")
      (insert (format ":ID:       %s\n" (org-id-new)))
      (insert ":END:\n")
      (insert "#+title: External Links\n")
      (insert "#+filetags: :tutoring:external_links:\n\n")
      (dolist (entry (nreverse sources))
        (let ((title (car entry))
              (links (cdr entry))
              (n 0))
          (insert (format "* %s\n" title))
          (dolist (link links)
            (cl-incf n)
            (cl-incf count)
            (let ((url (car link))
                  (desc (cdr link)))
              (if (and desc (not (string-empty-p (string-trim desc))))
                  (insert (format "- [[%s][%s]]\n" url desc))
                (insert (format "- [[%s][TODO RENAME: %s link %d]]\n"
                                url title n)))))
          (insert "\n")))
      (write-region (point-min) (point-max) target))
    (message "Migrated %d links from %d topics into %s"
             count (length sources) target)))

(after! org
  (map! :map org-mode-map
        :localleader
        :desc "Link material" "l m" #'my/org-insert-material-links
        :desc "Link external" "l e" #'my/org-insert-external-link
        :desc "Open link in vsplit" "l v" #'org-open-link-in-vsplit))

(after! image-mode
  (map! :map image-mode-map
        :n "RET" (cmd! (call-process "open" nil 0 nil (buffer-file-name)))))

