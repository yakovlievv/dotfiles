;;; +book-gallery.el --- Book gallery for org-roam -*- lexical-binding: t; -*-

;;; Customization

(defgroup book-gallery nil
  "Book gallery for org-roam."
  :group 'org-roam)

(defcustom book-gallery-refresh-interval 300
  "Auto-refresh interval in seconds. 0 to disable."
  :type 'integer :group 'book-gallery)

(defcustom book-gallery-cover-height 120
  "Height in pixels for cover thumbnails."
  :type 'integer :group 'book-gallery)

;;; State

(defvar book-gallery--filter-status nil)
(defvar book-gallery--filter-tag nil)
(defvar book-gallery--sort-key 'status)
(defvar book-gallery--refresh-timer nil)
(defvar book-gallery--clock-cache (make-hash-table :test 'equal))
(defvar book-gallery--books-cache nil)

;;; Data layer

(defun book-gallery--query-books ()
  "Return list of book plists from org-roam DB."
  (let* ((rows (org-roam-db-query
                [:select :distinct [nodes:id nodes:file nodes:title nodes:properties]
                 :from nodes
                 :inner-join tags :on (= nodes:id tags:node-id)
                 :where (= tags:tag "book")]))
         books)
    (dolist (row rows (nreverse books))
      (let* ((id (nth 0 row))
             (file (nth 1 row))
             (title (nth 2 row))
             (props (nth 3 row))
             (all-tags (mapcar #'car
                               (org-roam-db-query
                                [:select [tag] :from tags
                                 :where (= node-id $s1)] id)))
             (status (book-gallery--extract-status all-tags))
             (area-tags (book-gallery--extract-area-tags all-tags)))
        (push (list :id id :file file
                    :title (or title "Untitled")
                    :author (book-gallery--prop props "AUTHOR")
                    :cover-url (book-gallery--extract-cover-url props)
                    :rating (string-to-number (or (book-gallery--prop props "RATING") "0"))
                    :pages-read (string-to-number (or (book-gallery--prop props "PAGES_READ") "0"))
                    :total-pages (string-to-number (or (book-gallery--prop props "TOTAL_PAGES") "0"))
                    :status status
                    :area-tags area-tags
                    :clock-minutes (book-gallery--file-clock-minutes file)
                    :clock-this-week (book-gallery--file-clock-this-week file))
              books)))))

(defun book-gallery--prop (props key)
  (when props
    (let ((val (cdr (assoc key props))))
      (when (and val (not (string-empty-p val))) val))))

(defun book-gallery--extract-status (tags)
  (seq-find (lambda (tag) (member tag '("active" "finished" "planned"))) tags))

(defun book-gallery--extract-area-tags (tags)
  (seq-remove (lambda (tag) (member tag '("book" "active" "finished" "planned"))) tags))

;;; Clock time extraction

(defun book-gallery--file-clock-minutes (file)
  (condition-case nil
      (let* ((attrs (file-attributes file))
             (mtime (file-attribute-modification-time attrs))
             (cache-key (cons file mtime))
             (cached (gethash cache-key book-gallery--clock-cache)))
        (or cached
            (let ((minutes (book-gallery--parse-clock-minutes file)))
              (puthash cache-key minutes book-gallery--clock-cache)
              minutes)))
    (error 0)))

(defun book-gallery--parse-clock-minutes (file)
  (let ((total 0))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward
              "CLOCK: \\[\\([0-9-]+ [A-Za-z]+ [0-9:]+\\)\\]--\\[\\([0-9-]+ [A-Za-z]+ [0-9:]+\\)\\] => +\\([0-9]+\\):\\([0-9]+\\)"
              nil t)
        (setq total (+ total
                       (* 60 (string-to-number (match-string 3)))
                       (string-to-number (match-string 4))))))
    total))

(defun book-gallery--file-clock-this-week (file)
  "Parse CLOCK entries from FILE that fall within the current week."
  (condition-case nil
      (let ((total 0)
            (week-start (book-gallery--week-start)))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward
                  "CLOCK: \\[\\([0-9]+-[0-9]+-[0-9]+ [A-Za-z]+ [0-9:]+\\)\\]--\\[\\([0-9]+-[0-9]+-[0-9]+ [A-Za-z]+ [0-9:]+\\)\\] => +\\([0-9]+\\):\\([0-9]+\\)"
                  nil t)
            (let* ((start-str (match-string 1))
                   (hours (string-to-number (match-string 3)))
                   (mins (string-to-number (match-string 4)))
                   (start-time (date-to-time (replace-regexp-in-string " [A-Za-z]+ " " " start-str))))
              (when (time-less-p week-start start-time)
                (setq total (+ total (* 60 hours) mins))))))
        total)
    (error 0)))

(defun book-gallery--week-start ()
  "Return the timestamp of Monday 00:00 of the current week."
  (let* ((now (decode-time))
         (dow (nth 6 now))  ;; 0=Sun 1=Mon ... 6=Sat
         (days-since-mon (if (= dow 0) 6 (1- dow))))
    (encode-time 0 0 0
                 (- (nth 3 now) days-since-mon)
                 (nth 4 now) (nth 5 now))))

;;; Filtering & sorting

(defun book-gallery--filter-books (books)
  (let ((result books))
    (when book-gallery--filter-status
      (setq result (seq-filter
                    (lambda (b) (string= (plist-get b :status)
                                         book-gallery--filter-status))
                    result)))
    (when book-gallery--filter-tag
      (setq result (seq-filter
                    (lambda (b) (member book-gallery--filter-tag
                                        (plist-get b :area-tags)))
                    result)))
    result))

(defun book-gallery--sort-books (books)
  (sort (copy-sequence books)
        (pcase book-gallery--sort-key
          ('title  (lambda (a b) (string< (plist-get a :title) (plist-get b :title))))
          ('author (lambda (a b) (string< (or (plist-get a :author) "")
                                          (or (plist-get b :author) ""))))
          ('rating (lambda (a b) (> (plist-get a :rating) (plist-get b :rating))))
          ('status (lambda (a b) (< (book-gallery--status-order (plist-get a :status))
                                    (book-gallery--status-order (plist-get b :status))))))))

(defun book-gallery--status-order (status)
  (pcase status ("active" 0) ("planned" 1) ("finished" 2) (_ 3)))

;;; Rendering helpers

(defun book-gallery--status-face (status)
  (pcase status
    ("active"   '(:foreground "#1e1e2e" :background "#a6e3a1" :weight bold))
    ("finished" '(:foreground "#1e1e2e" :background "#89b4fa" :weight bold))
    ("planned"  '(:foreground "#1e1e2e" :background "#f9e2af" :weight bold))
    (_          '(:foreground "#1e1e2e" :background "#6c7086" :weight bold))))

(defun book-gallery--rating-string (rating)
  (let ((filled (make-string (min rating 5) ?*))
        (empty (make-string (max 0 (- 5 (min rating 5))) ?*)))
    (concat (propertize filled 'face '(:foreground "#f9e2af"))
            (propertize empty 'face '(:foreground "#45475a")))))

(defun book-gallery--progress-bar (current total)
  (let* ((pct (if (> total 0) (/ (* 100.0 current) total) 0))
         (bar-width 15)
         (filled (round (* bar-width (/ pct 100.0))))
         (empty (- bar-width filled)))
    (concat (propertize (make-string filled ?#) 'face '(:foreground "#a6e3a1"))
            (propertize (make-string empty ?-) 'face '(:foreground "#313244"))
            (propertize (format " %d%%" (round pct)) 'face '(:foreground "#6c7086")))))

(defun book-gallery--format-hours (minutes)
  "Format MINUTES as a human-readable hours string."
  (cond
   ((= minutes 0) "0h")
   ((< minutes 60) (format "%dm" minutes))
   (t (let ((h (/ minutes 60))
            (m (% minutes 60)))
        (if (= m 0) (format "%dh" h) (format "%dh%dm" h m))))))

;;; Cover image handling

(defvar book-gallery--cover-dir
  (expand-file-name "book-gallery-covers" (temporary-file-directory)))

(defun book-gallery--extract-cover-url (props)
  "Extract cover URL from PROPS, stripping org link brackets."
  (when-let ((raw (book-gallery--prop props "COVER")))
    (if (string-match "\\[\\[\\(.*?\\)\\]\\]" raw)
        (match-string 1 raw)
      raw)))

(defun book-gallery--cover-cache-path (url)
  "Return local cache path for cover URL."
  (unless (file-directory-p book-gallery--cover-dir)
    (make-directory book-gallery--cover-dir t))
  (expand-file-name (md5 url) book-gallery--cover-dir))

(defun book-gallery--download-cover (url)
  "Download cover from URL, return local path or nil."
  (condition-case nil
      (let ((cache-path (book-gallery--cover-cache-path url)))
        (if (file-exists-p cache-path)
            cache-path
          (url-copy-file url cache-path t)
          (when (file-exists-p cache-path) cache-path)))
    (error nil)))

(defun book-gallery--create-cover-image (file)
  "Create an Emacs image object from FILE, scaled to `book-gallery-cover-height'."
  (when (and file (file-exists-p file))
    (condition-case nil
        (create-image file nil nil :height book-gallery-cover-height :ascent 'center)
      (error nil))))

(defun book-gallery--status-svg (status width)
  "Create an SVG status badge WIDTH pixels wide."
  (let* ((label (upcase (or status "?")))
         (colors (pcase status
                   ("active"   '("#a6e3a1" "#1e1e2e"))
                   ("finished" '("#89b4fa" "#1e1e2e"))
                   ("planned"  '("#f9e2af" "#1e1e2e"))
                   (_          '("#6c7086" "#1e1e2e"))))
         (bg (car colors))
         (fg (cadr colors))
         (h 20)
         (svg (format
               "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>\
<rect width='%d' height='%d' rx='3' fill='%s'/>\
<text x='%d' y='%d' font-family='sans-serif' font-size='11' font-weight='bold' \
fill='%s' text-anchor='middle' dominant-baseline='central'>%s</text></svg>"
               width h width h bg (/ width 2) (/ h 2) fg label)))
    (create-image svg 'svg t :ascent 'center)))

;;; Entry rendering

(defun book-gallery--render-entry (book)
  "Render a single book entry: cover+title on line 1, status+meta on line 2."
  (let* ((title (plist-get book :title))
         (author (or (plist-get book :author) "Unknown"))
         (status (or (plist-get book :status) "?"))
         (rating (plist-get book :rating))
         (pages-read (plist-get book :pages-read))
         (total-pages (plist-get book :total-pages))
         (clock-min (plist-get book :clock-minutes))
         (area-tags (plist-get book :area-tags))
         (cover-url (plist-get book :cover-url))
         (file (plist-get book :file))
         (start (point))
         (cover-img (when cover-url
                      (when-let ((local (book-gallery--download-cover cover-url)))
                        (book-gallery--create-cover-image local))))
         (cover-px-w (when cover-img (car (image-size cover-img t))))
         (dot (propertize " · " 'face '(:foreground "#45475a"))))
    ;; Line 1: [cover]   Title  Author
    (insert "  ")
    (if cover-img
        (progn (insert-image cover-img "[cover]") (insert "   "))
      (insert "  "))
    (let ((title-start (point)))
      (insert (propertize title 'face '(:weight bold :height 1.1)))
      (put-text-property title-start (point) 'book-title t))
    (insert "  ")
    (insert (propertize author 'face '(:foreground "#a6adc8")))
    (insert "\n")
    ;; Line 2: [status badge]   rating · tags · progress · clock
    (insert "  ")
    (if (and cover-px-w (> cover-px-w 0))
        (progn
          (insert-image (book-gallery--status-svg status cover-px-w) "[status]")
          (insert "   "))
      (insert (propertize (format " %-8s " (capitalize status))
                          'face (book-gallery--status-face status))
              "   "))
    (insert (book-gallery--rating-string rating))
    (when area-tags
      (insert dot)
      (insert (mapconcat (lambda (tag)
                           (propertize tag 'face '(:foreground "#cba6f7")))
                         area-tags
                         (propertize ", " 'face '(:foreground "#45475a")))))
    (when (> total-pages 0)
      (insert dot)
      (insert (book-gallery--progress-bar pages-read total-pages)))
    (when (> clock-min 0)
      (insert dot)
      (insert (propertize (book-gallery--format-hours clock-min)
                          'face '(:foreground "#89b4fa"))))
    (insert "\n")
    ;; Spacer between entries
    (insert (propertize "\n" 'line-spacing 12))
    ;; Set book-file on entire entry
    (put-text-property start (point) 'book-file file)))

;;; Header

(defun book-gallery--render-header ()
  (let* ((all-books book-gallery--books-cache)
         (total (length all-books))
         (finished (length (seq-filter (lambda (b) (string= "finished" (plist-get b :status))) all-books)))
         (active (length (seq-filter (lambda (b) (string= "active" (plist-get b :status))) all-books)))
         (planned (length (seq-filter (lambda (b) (string= "planned" (plist-get b :status))) all-books)))
         (total-min (apply #'+ (mapcar (lambda (b) (plist-get b :clock-minutes)) all-books)))
         (week-min (apply #'+ (mapcar (lambda (b) (plist-get b :clock-this-week)) all-books))))
    ;; Title
    (insert (propertize "  Book Gallery" 'face '(:height 1.3 :weight bold)) "\n")
    ;; Stats
    (insert "  "
            (propertize (format "%d books" total) 'face '(:foreground "#cdd6f4"))
            (propertize " · " 'face '(:foreground "#45475a"))
            (propertize (format "%d finished" finished) 'face '(:foreground "#89b4fa"))
            (propertize " · " 'face '(:foreground "#45475a"))
            (propertize (format "%d active" active) 'face '(:foreground "#a6e3a1"))
            (propertize " · " 'face '(:foreground "#45475a"))
            (propertize (format "%d planned" planned) 'face '(:foreground "#f9e2af"))
            (propertize " · " 'face '(:foreground "#45475a"))
            (propertize (format "total %s" (book-gallery--format-hours total-min))
                        'face '(:foreground "#89b4fa"))
            (propertize " · " 'face '(:foreground "#45475a"))
            (propertize (format "this week %s" (book-gallery--format-hours week-min))
                        'face '(:foreground "#a6e3a1"))
            "\n\n")))

;;; Main render

(defun book-gallery--render ()
  "Render the book gallery."
  (condition-case err
      (let* ((inhibit-read-only t)
             (all-books (book-gallery--query-books))
             (books (book-gallery--sort-books
                     (book-gallery--filter-books all-books))))
        (setq book-gallery--books-cache all-books)
        (erase-buffer)
        (book-gallery--render-header)
        (if (null books)
            (insert (propertize "  No books found." 'face '(:foreground "#6c7086")))
          (dolist (book books)
            (book-gallery--render-entry book)))
        (book-gallery--goto-first-title))
    (error
     (let ((inhibit-read-only t))
       (erase-buffer)
       (insert (format "Book Gallery Error:\n\n%s" (error-message-string err)))))))

;;; Major mode

(defun book-gallery-open-at-point ()
  "Open the book file at point."
  (interactive)
  (if-let ((file (get-text-property (point) 'book-file)))
      (find-file file)
    (message "No book at point")))

(defvar book-gallery-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET")      #'book-gallery-open-at-point)
    (define-key map (kbd "<return>") #'book-gallery-open-at-point)
    (define-key map [mouse-1]        #'book-gallery-open-at-point)
    (define-key map (kbd "g")  #'book-gallery-refresh)
    (define-key map (kbd "q")  #'quit-window)
    map))

(define-derived-mode book-gallery-mode special-mode "BookGallery"
  "Major mode for the book gallery."
  (setq truncate-lines nil)
  (buffer-disable-undo)
  (add-hook 'post-command-hook #'book-gallery--snap-to-title nil t)
  (add-hook 'kill-buffer-hook #'book-gallery--cleanup nil t)
  (when (> book-gallery-refresh-interval 0)
    (setq book-gallery--refresh-timer
          (run-with-timer book-gallery-refresh-interval
                          book-gallery-refresh-interval
                          #'book-gallery--auto-refresh))))

(after! evil
  (evil-define-key 'normal book-gallery-mode-map
    (kbd "RET")      #'book-gallery-open-at-point
    (kbd "<return>") #'book-gallery-open-at-point
    "j"  #'book-gallery-next-book
    "k"  #'book-gallery-prev-book
    "gr" #'book-gallery-refresh
    "q"  #'quit-window))

(map! :map book-gallery-mode-map
      :localleader
      (:prefix ("f" . "filter")
       "a" #'book-gallery-filter-all
       "s" #'book-gallery-filter-status
       "t" #'book-gallery-filter-tag)
      (:prefix ("s" . "sort")
       "t" #'book-gallery-sort-title
       "a" #'book-gallery-sort-author
       "r" #'book-gallery-sort-rating
       "s" #'book-gallery-sort-status))

(defun book-gallery--cleanup ()
  (when book-gallery--refresh-timer
    (cancel-timer book-gallery--refresh-timer)
    (setq book-gallery--refresh-timer nil)))

(defun book-gallery--auto-refresh ()
  (when-let ((buf (get-buffer "*Book Gallery*")))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (book-gallery--render)))))

;;; Interactive commands

;;;###autoload
(defun book-gallery ()
  "Open the book gallery."
  (interactive)
  (let ((buf (get-buffer-create "*Book Gallery*")))
    (with-current-buffer buf
      (unless (eq major-mode 'book-gallery-mode)
        (book-gallery-mode))
      (book-gallery--render))
    (switch-to-buffer buf)))

(defun book-gallery-refresh ()
  "Refresh the gallery."
  (interactive)
  (when (eq major-mode 'book-gallery-mode)
    (let ((pos (point)))
      (book-gallery--render)
      (goto-char (min pos (point-max))))))

(defun book-gallery-filter-all ()
  (interactive)
  (setq book-gallery--filter-status nil
        book-gallery--filter-tag nil)
  (book-gallery-refresh))

(defun book-gallery-filter-status ()
  (interactive)
  (let ((choice (completing-read "Status: " '("all" "active" "finished" "planned"))))
    (setq book-gallery--filter-status (unless (string= choice "all") choice))
    (book-gallery-refresh)))

(defun book-gallery-filter-tag ()
  (interactive)
  (let* ((all-tags (mapcar #'car
                           (org-roam-db-query
                            [:select :distinct [tag] :from tags
                             :where (not-in tag $v1)]
                            (vector "book" "active" "finished" "planned"))))
         (choice (completing-read "Area tag (empty for all): " (cons "" all-tags))))
    (setq book-gallery--filter-tag (if (string-empty-p choice) nil choice))
    (book-gallery-refresh)))

(defun book-gallery-sort-title ()  (interactive) (setq book-gallery--sort-key 'title) (book-gallery-refresh))
(defun book-gallery-sort-author () (interactive) (setq book-gallery--sort-key 'author) (book-gallery-refresh))
(defun book-gallery-sort-rating () (interactive) (setq book-gallery--sort-key 'rating) (book-gallery-refresh))
(defun book-gallery-sort-status () (interactive) (setq book-gallery--sort-key 'status) (book-gallery-refresh))

(defun book-gallery--goto-first-title ()
  "Move cursor to the first book title in the buffer."
  (goto-char (point-min))
  (let ((pos (next-single-property-change (point) 'book-title)))
    (when pos (goto-char pos))))

(defun book-gallery-next-book ()
  "Jump to the next book title."
  (interactive)
  (let ((end (next-single-property-change (point) 'book-title)))
    (when end
      (let ((next (next-single-property-change end 'book-title)))
        (when next (goto-char next))))))

(defun book-gallery-prev-book ()
  "Jump to the previous book title."
  (interactive)
  (let ((start (previous-single-property-change (point) 'book-title)))
    (when (and start (> start (point-min)))
      (let ((prev (previous-single-property-change start 'book-title)))
        (when prev (goto-char prev))))))

(defun book-gallery--snap-to-title ()
  "Snap cursor to the nearest book title. Used in `post-command-hook'."
  (when (eq major-mode 'book-gallery-mode)
    (unless (get-text-property (point) 'book-title)
      (let ((fwd (next-single-property-change (point) 'book-title))
            (bwd (previous-single-property-change (point) 'book-title)))
        ;; Find closest title position
        (let ((fwd-pos (when fwd
                         (if (get-text-property fwd 'book-title) fwd
                           (next-single-property-change fwd 'book-title))))
              (bwd-pos (when (and bwd (> bwd (point-min)))
                         (if (get-text-property bwd 'book-title) bwd
                           (let ((p (previous-single-property-change bwd 'book-title)))
                             (when p (if (get-text-property p 'book-title) p
                                       (next-single-property-change p 'book-title))))))))
          (cond
           ((and fwd-pos bwd-pos)
            (goto-char (if (<= (- fwd-pos (point)) (- (point) bwd-pos))
                           fwd-pos bwd-pos)))
           (fwd-pos (goto-char fwd-pos))
           (bwd-pos (goto-char bwd-pos))))))))

;; Keybinding
(map! :leader :desc "Book gallery" "o b" #'book-gallery)

(provide '+book-gallery)
;;; +book-gallery.el ends here
