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
  "Window reused by `org-open-link-in-vsplit'.")

(defun org-open-link-in-vsplit ()
  "Open org link at point in a vertical split, reusing the same window.
Cursor stays in the original window."
  (interactive)
  (let ((orig-window (selected-window))
        (org-link-frame-setup
         (cons `(file . ,(lambda (f)
                           (if (and org-link-vsplit-window
                                    (window-live-p org-link-vsplit-window))
                               (progn
                                 (select-window org-link-vsplit-window)
                                 (find-file f))
                             (let ((win (split-window-right)))
                               (setq org-link-vsplit-window win)
                               (select-window win)
                               (find-file f)))))
               org-link-frame-setup)))
    (org-open-at-point)
    (select-window orig-window)))

(defun my/org-insert-material-links ()
  "Pick material files and insert as org links.
TAB marks/unmarks files, RET inserts all marked."
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
    (minibuffer-with-setup-hook
        (lambda () (use-local-map (make-composed-keymap keymap (current-local-map))))
      (completing-read
       "Material (TAB mark, RET confirm): "
       (lambda (str pred action)
         (if (eq action 'metadata)
             (list 'metadata
                   (cons 'annotation-function
                         (lambda (cand)
                           (if (member cand selected) " [x]" ""))))
           (complete-with-action action candidates str pred)))))
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

