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
      :desc "Lesson dashboard" "n l" #'lesson-dashboard
      :desc "Dirvish" "e" #'dirvish)

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
  "When the current buffer shows an image or PDF page, resize the window to its rendered width."
  (let ((img (cond
              ((and (derived-mode-p 'image-mode)
                    (image-get-display-property)))
              ((and (derived-mode-p 'pdf-view-mode)
                    (fboundp 'pdf-view-current-image)
                    (pdf-view-current-image))))))
    (when (and img (not (one-window-p)))
      (redisplay t)
      (let* ((img-w-px (car (image-display-size img t)))
             (pad-px (* 2 (frame-char-width)))
             (target-px (+ img-w-px pad-px))
             (delta-px (- target-px (window-body-width nil t))))
        (when (/= 0 delta-px)
          (ignore-errors
            (window-resize nil delta-px t nil t)))))))

(defun my/preview-file-in-vsplit (file)
  "Show FILE in the vsplit preview window."
  (let ((win (my/ensure-vsplit-window)))
    (with-selected-window win
      (find-file file)
      (display-line-numbers-mode -1)
      (my/fit-window-to-image))))

(defun my/org-link-roam-target-p (file)
  "Return non-nil if FILE lives under `org-roam-directory'."
  (when-let* ((file file)
              (roam-dir (and (boundp 'org-roam-directory) org-roam-directory)))
    (file-in-directory-p file roam-dir)))

(defun my/org-link-target-at-point ()
  "Return the file path of the org link at point, or nil.
Org-roam links (id: links resolving inside `org-roam-directory') are ignored."
  (let ((ctx (org-element-context)))
    (when (eq (org-element-type ctx) 'link)
      (let* ((type (org-element-property :type ctx))
             (path (org-element-property :path ctx))
             (target (cond
                      ((string= type "file") (expand-file-name path))
                      ((string= type "id")
                       (when-let ((loc (org-id-find path)))
                         (car loc)))
                      (t nil))))
        (unless (my/org-link-roam-target-p target)
          target)))))

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
  "Kill every image/PDF preview buffer so previews re-render fresh."
  (dolist (buf (buffer-list))
    (when (with-current-buffer buf
            (or (derived-mode-p 'image-mode)
                (derived-mode-p 'pdf-view-mode)))
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
                        (abbreviate-file-name
                         (alist-get rel rel-alist nil nil #'equal))))))))

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

(defun my/org-rewrite-link-paths (mapping)
  "Rewrite org `file:' links across ~/org/ according to MAPPING.
MAPPING is an alist of (OLD-ABS . NEW-ABS) absolute paths. For each
pair both the absolute (file:/Users/...) and tilde (file:~/...) link
forms are replaced. Returns a cons (FILES-MODIFIED . REPLACEMENTS)."
  (let* ((home (expand-file-name "~/"))
         (forms
          (apply
           #'append
           (mapcar
            (lambda (pair)
              (let* ((old (expand-file-name (car pair)))
                     (new (expand-file-name (cdr pair)))
                     (acc (list (cons (concat "file:" old)
                                      (concat "file:" new)))))
                (when (and (string-prefix-p home old)
                           (string-prefix-p home new))
                  (push (cons (concat "file:~/" (substring old (length home)))
                              (concat "file:~/" (substring new (length home))))
                        acc))
                acc))
            mapping)))
         (root (expand-file-name "~/org/"))
         (files-modified 0)
         (replacements 0))
    (dolist (org-file (directory-files-recursively
                       root "\\.org\\'" nil
                       (lambda (sub)
                         (not (string-prefix-p
                               "." (file-name-nondirectory
                                    (directory-file-name sub)))))))
      (with-temp-buffer
        (insert-file-contents org-file)
        (let ((original (buffer-string))
              (local 0))
          (dolist (form forms)
            (goto-char (point-min))
            (while (search-forward (car form) nil t)
              (replace-match (cdr form) t t)
              (cl-incf local)))
          (unless (string= original (buffer-string))
            (write-region (point-min) (point-max) org-file nil 'silent)
            (cl-incf files-modified)
            (cl-incf replacements local)))))
    (cons files-modified replacements)))

(defun my/org-move-path--smart-source ()
  "Return a sensible default source path for `my/org-move-path', or nil."
  (cond
   ((derived-mode-p 'dired-mode)
    (ignore-errors (dired-get-filename nil t)))
   ((derived-mode-p 'org-mode)
    (when-let* ((target (my/org-link-target-at-point))
                ((file-exists-p target)))
      target))))

(defun my/org-move-path--resolve-destination (src dst-raw)
  "Resolve user-typed DST-RAW into the final absolute destination for SRC.
If DST-RAW points to an existing directory or ends with /, the source
basename is appended; otherwise DST-RAW is treated as the full new path."
  (let ((dst (expand-file-name dst-raw)))
    (if (or (file-directory-p dst)
            (string-suffix-p "/" dst-raw))
        (expand-file-name (file-name-nondirectory
                           (directory-file-name src))
                          dst)
      dst)))

(defun my/org-move-path--build-mapping (src dst)
  "Build (OLD . NEW) alist of file paths for moving SRC to DST.
For a directory SRC, returns one pair per descendant file with
substructure preserved under DST."
  (if (file-directory-p src)
      (mapcar (lambda (f)
                (cons f (expand-file-name (file-relative-name f src) dst)))
              (directory-files-recursively src ""))
    (list (cons src dst))))

(defun my/org-move-path (src dst)
  "Move SRC to DST and rewrite every org `file:' link that referenced
SRC (or anything under it) across ~/org/.

Interactive defaults: file-at-point in dired, link-target in org-mode,
otherwise `read-file-name' rooted at ~/org/material/. If DST is an
existing directory (or ends with /), the source basename is appended.
Missing parent directories are created. Overwrite is refused without
explicit confirmation."
  (interactive
   (let* ((default (my/org-move-path--smart-source))
          (src (or default
                   (read-file-name
                    "Move: " (expand-file-name "~/org/material/")
                    nil t))))
     (list (expand-file-name src)
           (read-file-name
            (format "Move %s to: " (abbreviate-file-name src))
            (file-name-directory src)))))
  (let* ((src (expand-file-name src))
         (dst (my/org-move-path--resolve-destination src dst)))
    (unless (file-exists-p src)
      (user-error "Source does not exist: %s" src))
    (when (string= src dst)
      (user-error "Source and destination are the same"))
    (when (and (file-exists-p dst)
               (not (yes-or-no-p
                     (format "%s exists. Overwrite? "
                             (abbreviate-file-name dst)))))
      (user-error "Aborted"))
    (let* ((mapping (my/org-move-path--build-mapping src dst))
           (n (length mapping)))
      (unless (yes-or-no-p
               (format "Move %s (%d file%s); rewrite links in ~/org/. Continue? "
                       (abbreviate-file-name src) n (if (= n 1) "" "s")))
        (user-error "Aborted"))
      (make-directory (file-name-directory dst) t)
      (rename-file src dst t)
      (let ((result (my/org-rewrite-link-paths mapping)))
        (when (derived-mode-p 'dired-mode)
          (revert-buffer nil t))
        (message "Moved to %s; rewrote %d link(s) across %d org file(s)"
                 (abbreviate-file-name dst)
                 (cdr result) (car result))))))

(defun my/org--rename-link-sync (orig-fn from to ok-if-already-exists)
  "Around-advice on `dired-rename-file': capture FROM/TO, delegate, then
rewrite org links so anything pointing to FROM (or under it) now points
to TO. Silent when no org link matches."
  (let* ((from-abs (expand-file-name from))
         (to-abs (expand-file-name to))
         (mapping (if (file-directory-p from-abs)
                      (mapcar (lambda (f)
                                (cons f (expand-file-name
                                         (file-relative-name f from-abs)
                                         to-abs)))
                              (directory-files-recursively from-abs ""))
                    (list (cons from-abs to-abs)))))
    (funcall orig-fn from to ok-if-already-exists)
    (when mapping
      (let ((result (my/org-rewrite-link-paths mapping)))
        (when (> (cdr result) 0)
          (message "Rewrote %d org link(s) in %d file(s)"
                   (cdr result) (car result)))))))

(after! dired
  (advice-add 'dired-rename-file :around #'my/org--rename-link-sync))

(map! :leader
      :desc "Move file (sync org links)" "f M" #'my/org-move-path)

(after! org
  (map! :map org-mode-map
        :localleader
        :desc "Link material" "l m" #'my/org-insert-material-links
        :desc "Link external" "l e" #'my/org-insert-external-link
        :desc "Open link in vsplit" "l v" #'org-open-link-in-vsplit))

(after! image-mode
  (map! :map image-mode-map
        :n "RET" (cmd! (call-process "open" nil 0 nil (buffer-file-name)))))

(defun my/org-image-link-at-point ()
  "Return absolute path if point is on an org link to an image file."
  (let ((ctx (org-element-context)))
    (when (eq (org-element-type ctx) 'link)
      (let ((type (org-element-property :type ctx))
            (path (org-element-property :path ctx)))
        (when (and (member type '("file" "attachment"))
                   path
                   (string-match-p (image-file-name-regexp) path))
          (expand-file-name path))))))

(defun my/org-ret-dwim ()
  "Open image links in macOS default app; otherwise fall back to `+org/dwim-at-point'."
  (interactive)
  (if-let ((img (my/org-image-link-at-point)))
      (call-process "open" nil 0 nil img)
    (call-interactively #'+org/dwim-at-point)))

(after! org
  (map! :map org-mode-map
        :n "RET" #'my/org-ret-dwim))

