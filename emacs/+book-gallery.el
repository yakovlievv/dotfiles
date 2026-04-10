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

(defcustom book-gallery-weekly-goal-minutes 120
  "Weekly reading goal in minutes. 0 to disable."
  :type 'integer :group 'book-gallery)

(defcustom book-gallery-google-books-api-key "AIzaSyAC0eAET4yidxFFPwUZ_iEdCPBM_A00AZk"
  "Google Books API key for ISBN lookups."
  :type 'string :group 'book-gallery)

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
                    :clock-today (book-gallery--file-clock-today file)
                    :clock-this-week (book-gallery--file-clock-this-week file)
                    :clock-year (book-gallery--file-clock-year file)
                    :last-read (book-gallery--file-last-read file)
                    :started (book-gallery--file-started file)
                    :link-count (book-gallery--file-link-count file))
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

(defun book-gallery--collect-daily-minutes (files)
  "Collect reading minutes per date across all FILES. Returns hash: date-string → minutes."
  (let ((daily (make-hash-table :test 'equal)))
    (dolist (file files daily)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (while (re-search-forward
                    "CLOCK: \\[\\([0-9]+-[0-9]+-[0-9]+\\) [A-Za-z]+ [0-9:]+\\]--\\[\\([0-9]+-[0-9]+-[0-9]+\\) [A-Za-z]+ [0-9:]+\\] => +\\([0-9]+\\):\\([0-9]+\\)"
                    nil t)
              (let* ((date (match-string 1))
                     (hours (string-to-number (match-string 3)))
                     (mins (string-to-number (match-string 4)))
                     (total (+ (* 60 hours) mins)))
                (puthash date (+ (gethash date daily 0) total) daily))))
        (error nil)))))

(defun book-gallery--file-last-read (file)
  "Return the most recent CLOCK end date from FILE as a string, or nil."
  (condition-case nil
      (let (latest)
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward
                  "CLOCK: \\[.*?\\]--\\[\\([0-9]+-[0-9]+-[0-9]+\\) [A-Za-z]+ [0-9:]+\\]"
                  nil t)
            (setq latest (match-string 1))))
        latest)
    (error nil)))

(defun book-gallery--file-started (file)
  "Return the earliest CLOCK start date from FILE as a string, or nil."
  (condition-case nil
      (let (earliest)
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward
                 "CLOCK: \\[\\([0-9]+-[0-9]+-[0-9]+\\) [A-Za-z]+ [0-9:]+\\]"
                 nil t)
            (setq earliest (match-string 1))))
        earliest)
    (error nil)))

(defun book-gallery--file-link-count (file)
  "Count org-roam links (id: links) in FILE."
  (condition-case nil
      (let ((count 0))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward "\\[\\[id:" nil t)
            (setq count (1+ count))))
        count)
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

(defun book-gallery--parse-org-time (str)
  "Parse an org timestamp string like '2026-03-22 Sun 20:48' into a time value."
  (let ((clean (replace-regexp-in-string " [A-Za-z]+ " "T" str)))
    (date-to-time (concat clean ":00"))))

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
                   (start-time (book-gallery--parse-org-time start-str)))
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

(defun book-gallery--today-start ()
  "Return the timestamp of today 00:00."
  (let ((now (decode-time)))
    (encode-time 0 0 0 (nth 3 now) (nth 4 now) (nth 5 now))))

(defun book-gallery--year-start ()
  "Return the timestamp of Jan 1 00:00 of the current year."
  (let ((now (decode-time)))
    (encode-time 0 0 0 1 1 (nth 5 now))))

(defun book-gallery--file-clock-today (file)
  "Parse CLOCK entries from FILE that fall within today."
  (condition-case nil
      (let ((total 0)
            (today (book-gallery--today-start)))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward
                  "CLOCK: \\[\\([0-9]+-[0-9]+-[0-9]+ [A-Za-z]+ [0-9:]+\\)\\]--\\[\\([0-9]+-[0-9]+-[0-9]+ [A-Za-z]+ [0-9:]+\\)\\] => +\\([0-9]+\\):\\([0-9]+\\)"
                  nil t)
            (let* ((start-str (match-string 1))
                   (hours (string-to-number (match-string 3)))
                   (mins (string-to-number (match-string 4)))
                   (start-time (book-gallery--parse-org-time start-str)))
              (when (time-less-p today start-time)
                (setq total (+ total (* 60 hours) mins))))))
        total)
    (error 0)))

(defun book-gallery--file-clock-year (file)
  "Parse CLOCK entries from FILE that fall within the current year."
  (condition-case nil
      (let ((total 0)
            (year-start (book-gallery--year-start)))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward
                  "CLOCK: \\[\\([0-9]+-[0-9]+-[0-9]+ [A-Za-z]+ [0-9:]+\\)\\]--\\[\\([0-9]+-[0-9]+-[0-9]+ [A-Za-z]+ [0-9:]+\\)\\] => +\\([0-9]+\\):\\([0-9]+\\)"
                  nil t)
            (let* ((start-str (match-string 1))
                   (hours (string-to-number (match-string 3)))
                   (mins (string-to-number (match-string 4)))
                   (start-time (book-gallery--parse-org-time start-str)))
              (when (time-less-p year-start start-time)
                (setq total (+ total (* 60 hours) mins))))))
        total)
    (error 0)))

;;; Streak

(defun book-gallery--calculate-streak (daily-hash)
  "Calculate current reading streak (consecutive days) from DAILY-HASH."
  (let ((streak 0)
        (today (decode-time)))
    (catch 'done
      (dotimes (i 365)
        (let* ((date-time (encode-time 0 0 0
                                       (- (nth 3 today) i)
                                       (nth 4 today)
                                       (nth 5 today)))
               (date-str (format-time-string "%Y-%m-%d" date-time))
               (mins (gethash date-str daily-hash 0)))
          (if (> mins 0)
              (setq streak (1+ streak))
            ;; Allow today to be 0 (haven't read yet today)
            (when (> i 0) (throw 'done nil))))))
    streak))

;;; Heatmap

(defcustom book-gallery-heatmap-weeks 12
  "Number of weeks to show in the reading heatmap."
  :type 'integer :group 'book-gallery)

(defun book-gallery--heatmap-color (minutes)
  "Return a color for MINUTES of reading."
  (cond
   ((= minutes 0)  "#313244")
   ((< minutes 30)  "#585b70")
   ((< minutes 60)  "#74c7a4")
   ((< minutes 120) "#a6e3a1")
   (t               "#94e2d5")))

(defun book-gallery--render-heatmap (daily-hash)
  "Render a reading heatmap from DAILY-HASH (date → minutes)."
  (let* ((weeks book-gallery-heatmap-weeks)
         (today (decode-time))
         (today-dow (nth 6 today))  ;; 0=Sun
         ;; Days from today back to the Monday of `weeks` ago
         (days-back (+ (* (1- weeks) 7)
                       (if (= today-dow 0) 6 (1- today-dow))))
         (day-names '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun")))
    (insert "\n")
    ;; Row per day of week
    (dotimes (day-idx 7)
      (insert "  "
              (propertize (nth day-idx day-names) 'face '(:foreground "#6c7086"))
              "  ")
      (dotimes (week-idx weeks)
        (let* ((offset (- days-back (- (* (- (1- weeks) week-idx) 7)
                                        day-idx)))
               ;; Calculate the date for this cell
               (cell-time (encode-time 0 0 0
                                       (- (nth 3 today) (- days-back
                                                           (* week-idx 7)
                                                           day-idx))
                                       (nth 4 today)
                                       (nth 5 today)))
               (date-str (format-time-string "%Y-%m-%d" cell-time))
               (mins (gethash date-str daily-hash 0))
               (color (book-gallery--heatmap-color mins))
               (future-p (time-less-p (current-time) cell-time)))
          (insert (if future-p
                      (propertize " " 'face '(:foreground "#1e1e2e"))
                    (propertize "■" 'face `(:foreground ,color)))
                  " ")))
      (insert "\n"))
    (insert "\n")))

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
    (when book-gallery--filter-title
      (let ((query (downcase book-gallery--filter-title)))
        (setq result (seq-filter
                      (lambda (b) (string-match-p query (downcase (plist-get b :title))))
                      result))))
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

(defun book-gallery--progress-bar (current total &optional status)
  (let* ((pct (if (> total 0) (/ (* 100.0 current) total) 0))
         (bar-width 15)
         (filled (round (* bar-width (/ pct 100.0))))
         (empty (- bar-width filled))
         (bar-color (pcase status
                      ("active"   "#a6e3a1")
                      ("finished" "#89b4fa")
                      ("planned"  "#f9e2af")
                      (_          "#a6e3a1"))))
    (concat (propertize (make-string filled ?#) 'face `(:foreground ,bar-color))
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
         (last-read (plist-get book :last-read))
         (started (plist-get book :started))
         (link-count (plist-get book :link-count))
         (area-tags (plist-get book :area-tags))
         (cover-url (plist-get book :cover-url))
         (file (plist-get book :file))
         (start (point))
         (cover-img (when cover-url
                      (when-let ((local (book-gallery--download-cover cover-url)))
                        (book-gallery--create-cover-image local))))
         (cover-px-w (when cover-img (car (image-size cover-img t))))
         (dot (propertize " · " 'face '(:foreground "#45475a")))
         (clocking-p (and (fboundp 'org-clocking-p)
                          (org-clocking-p)
                          (eq (marker-buffer org-clock-marker)
                              (get-file-buffer file)))))
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
    (when clocking-p
      (insert "  " (propertize "● reading" 'face '(:foreground "#a6e3a1" :weight bold))))
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
      (insert (book-gallery--progress-bar pages-read total-pages status)))
    (when (> clock-min 0)
      (insert dot)
      (insert (propertize (book-gallery--format-hours clock-min)
                          'face '(:foreground "#89b4fa"))))
    ;; Reading pace: pages/hr + estimated time left
    (when (and (> clock-min 0) (> pages-read 0))
      (let* ((pages-per-hr (/ (* 60.0 pages-read) clock-min))
             (remaining (- total-pages pages-read))
             (hrs-left (if (> pages-per-hr 0) (/ remaining pages-per-hr) 0)))
        (insert dot)
        (insert (propertize (format "%.0f p/hr" pages-per-hr) 'face '(:foreground "#cba6f7")))
        (when (and (> remaining 0) (> hrs-left 0))
          (insert (propertize (format " ~%s left" (book-gallery--format-hours (round (* 60 hrs-left))))
                              'face '(:foreground "#6c7086"))))))
    ;; Links
    (when (> link-count 0)
      (insert dot)
      (insert (propertize (format "%d %s" link-count (if (= link-count 1) "link" "links"))
                    'face '(:foreground "#94e2d5"))))
    ;; Started date
    (when started
      (insert dot)
      (insert (propertize (concat "from " started) 'face '(:foreground "#6c7086"))))
    ;; Last read
    (when last-read
      (insert dot)
      (insert (propertize last-read 'face '(:foreground "#6c7086"))))
    (insert "\n")
    ;; Spacer between entries
    (insert (propertize "\n" 'line-spacing 12))
    ;; Set book-file on entire entry
    (put-text-property start (point) 'book-file file)))

;;; Header

(defvar book-gallery--daily-cache nil
  "Hash table of date → minutes for the heatmap.")

(defun book-gallery--render-header ()
  (let* ((all-books book-gallery--books-cache)
         (total (length all-books))
         (finished (length (seq-filter (lambda (b) (string= "finished" (plist-get b :status))) all-books)))
         (active (length (seq-filter (lambda (b) (string= "active" (plist-get b :status))) all-books)))
         (planned (length (seq-filter (lambda (b) (string= "planned" (plist-get b :status))) all-books)))
         (today-min (apply #'+ (mapcar (lambda (b) (plist-get b :clock-today)) all-books)))
         (week-min (apply #'+ (mapcar (lambda (b) (plist-get b :clock-this-week)) all-books)))
         (year-min (apply #'+ (mapcar (lambda (b) (plist-get b :clock-year)) all-books)))
         (year-str (substring (format-time-string "%Y") 0 4))
         (year-finished (length (seq-filter
                                 (lambda (b)
                                   (and (string= "finished" (plist-get b :status))
                                        (let ((lr (plist-get b :last-read)))
                                          (and lr (string-prefix-p year-str lr)))))
                                 all-books))))
    ;; Stats
    (let* ((dot (propertize " · " 'face '(:foreground "#45475a")))
           (streak (if book-gallery--daily-cache
                       (book-gallery--calculate-streak book-gallery--daily-cache)
                     0))
           (streak-str (if (> streak 0)
                           (concat (propertize "󰈸" 'face '(:foreground "#f9e2af"))
                                   (propertize (format " %d" streak)
                                               'face '(:foreground "#f9e2af")))
                         (propertize "󰈸 0" 'face '(:foreground "#45475a"))))
           (goal book-gallery-weekly-goal-minutes)
           (show-goal (> goal 0))
           (bar-w 10)
           (pct (if show-goal (min 100 (round (* 100.0 (/ (float week-min) goal)))) 0))
           (filled (round (* bar-w (/ pct 100.0))))
           (empty (- bar-w filled))
           (color "#a6e3a1"))
      (insert "  "
              (propertize (format "%d total" total) 'face '(:foreground "#cdd6f4"))
              dot
              (propertize (number-to-string active) 'face '(:foreground "#a6e3a1"))
              (propertize "-" 'face '(:foreground "#45475a"))
              (propertize (number-to-string finished) 'face '(:foreground "#89b4fa"))
              (propertize "-" 'face '(:foreground "#45475a"))
              (propertize (number-to-string planned) 'face '(:foreground "#f9e2af"))
              dot
              (propertize "year " 'face '(:foreground "#89b4fa"))
              (propertize (book-gallery--format-hours year-min) 'face '(:foreground "#89b4fa"))
              (propertize "-" 'face '(:foreground "#45475a"))
              (propertize (format "%d %s" year-finished (if (= year-finished 1) "book" "books"))
                          'face '(:foreground "#89b4fa"))
              dot
              (propertize (format "week %s" (book-gallery--format-hours week-min))
                          'face '(:foreground "#a6e3a1"))
              (if show-goal
                  (concat (propertize (format "/%s " (book-gallery--format-hours goal))
                                      'face '(:foreground "#45475a"))
                          (propertize (make-string filled ?#) 'face `(:foreground ,color))
                          (propertize (make-string empty ?-) 'face '(:foreground "#313244")))
                "")
              dot
              (propertize (format "today %s" (book-gallery--format-hours today-min))
                          'face '(:foreground "#f9e2af"))
              dot
              (propertize (symbol-name book-gallery--sort-key)
                          'face '(:foreground "#6c7086"))
              (if book-gallery--filter-status
                  (concat (propertize " · " 'face '(:foreground "#313244"))
                          (propertize book-gallery--filter-status 'face '(:foreground "#6c7086")))
                "")
              (if book-gallery--filter-tag
                  (concat (propertize " · " 'face '(:foreground "#313244"))
                          (propertize book-gallery--filter-tag 'face '(:foreground "#6c7086")))
                "")
              (if book-gallery--filter-title
                  (concat (propertize " · " 'face '(:foreground "#313244"))
                          (propertize (concat "/" book-gallery--filter-title) 'face '(:foreground "#6c7086")))
                "")
              (propertize " " 'display `(space :align-to (- right ,(+ 2 (length (format "󰈸 %d" streak))))))
              streak-str
              "\n")
      ;; Heatmap
      (when book-gallery--daily-cache
        (book-gallery--render-heatmap book-gallery--daily-cache)))))

;;; Main render

(defun book-gallery--render ()
  "Render the book gallery."
  (condition-case err
      (let* ((inhibit-read-only t)
             (all-books (book-gallery--query-books))
             (books (book-gallery--sort-books
                     (book-gallery--filter-books all-books))))
        (setq book-gallery--books-cache all-books)
        (setq book-gallery--daily-cache
              (book-gallery--collect-daily-minutes
               (mapcar (lambda (b) (plist-get b :file)) all-books)))
        (erase-buffer)
        (book-gallery--render-header)
        (if (null books)
            (insert (propertize "  No books found." 'face '(:foreground "#6c7086")))
          (dolist (book books)
            (book-gallery--render-entry book)))
        (setq-local truncate-lines t)
        (setq-local display-line-numbers nil)
        (book-gallery--goto-first-title))
    (error
     (let ((inhibit-read-only t))
       (erase-buffer)
       (insert (format "Library Error:\n\n%s" (error-message-string err)))))))

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
  (setq-local truncate-lines t)
  (setq-local truncate-partial-width-windows nil)
  (setq-local word-wrap nil)
  (setq-local display-line-numbers nil)
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
    (kbd "j")   #'book-gallery-next-book
    (kbd "k")   #'book-gallery-prev-book
    (kbd "n")   #'book-gallery-new-book
    (kbd "I")   #'book-gallery-new-from-isbn
    (kbd "i")   #'book-gallery-fill-from-isbn
    (kbd "D")   #'book-gallery-mark-done
    (kbd "A")   #'book-gallery-mark-active
    (kbd "P")   #'book-gallery-mark-planned
    (kbd "o")   #'book-gallery-open-hsplit
    (kbd "O")   #'book-gallery-open-vsplit
    (kbd "p")   #'book-gallery-set-pages
    (kbd "c")   #'book-gallery-toggle-clock
    (kbd "1")   (lambda () (interactive) (book-gallery-set-rating 1))
    (kbd "2")   (lambda () (interactive) (book-gallery-set-rating 2))
    (kbd "3")   (lambda () (interactive) (book-gallery-set-rating 3))
    (kbd "4")   (lambda () (interactive) (book-gallery-set-rating 4))
    (kbd "5")   (lambda () (interactive) (book-gallery-set-rating 5))
    (kbd "/")   #'book-gallery-search
    (kbd "?")   #'book-gallery-help
    (kbd "g r") #'book-gallery-refresh
    (kbd "q")   #'quit-window))

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
  (when-let ((buf (get-buffer "*yako's library*")))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (book-gallery--render)))))

;;; Interactive commands

;;;###autoload
(defun book-gallery ()
  "Open the book gallery."
  (interactive)
  (let ((buf (get-buffer-create "*yako's library*")))
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
        book-gallery--filter-tag nil
        book-gallery--filter-title nil)
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

(defun book-gallery-new-book ()
  "Create a new book using the org-roam book capture template."
  (interactive)
  (org-roam-capture nil nil
                    :templates (list +org-roam-book-capture-template)))

(defun book-gallery--isbn-fetch-json (url)
  "Fetch URL and parse JSON response. Signals descriptive errors on failure."
  (let ((buf (condition-case nil
                 (url-retrieve-synchronously url t nil 10)
               (error nil))))
    (unless buf
      (error "Network error: could not connect to Google Books API. Check your internet connection"))
    (with-current-buffer buf
      (goto-char (point-min))
      ;; Extract HTTP status code
      (let ((status-code nil))
        (when (re-search-forward "^HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
          (setq status-code (string-to-number (match-string 1))))
        (re-search-forward "\n\n" nil t)
        (set-buffer-multibyte t)
        (decode-coding-region (point) (point-max) 'utf-8)
        (let ((json (condition-case nil
                        (json-read)
                      (error (kill-buffer) (error "Failed to parse API response")))))
          (kill-buffer)
          ;; Check for API error response
          (let ((api-error (cdr (assq 'error json))))
            (when api-error
              (let* ((code (cdr (assq 'code api-error)))
                     (msg (cdr (assq 'message api-error)))
                     (reason (let* ((errs (cdr (assq 'errors api-error)))
                                    (first-err (when (and errs (> (length errs) 0))
                                                 (aref errs 0))))
                               (when first-err (cdr (assq 'reason first-err))))))
                (error "Google Books API error %s: %s"
                       (or code status-code "unknown")
                       (cond
                        ((equal reason "rateLimitExceeded")
                         "Daily quota exceeded. Try again tomorrow or check your API key quota at console.cloud.google.com")
                        ((equal reason "keyInvalid")
                         "Invalid API key. Check book-gallery-google-books-api-key")
                        ((equal reason "keyExpired")
                         "API key expired. Generate a new one at console.cloud.google.com")
                        ((equal reason "accessNotConfigured")
                         "Books API not enabled. Enable it at console.cloud.google.com → APIs & Services")
                        ((eql code 403)
                         (format "Forbidden: %s" (or msg "access denied")))
                        ((eql code 400)
                         (format "Bad request: %s" (or msg "check ISBN format")))
                        ((eql code 500)
                         "Google server error. Try again later")
                        ((eql code 503)
                         "Google Books API temporarily unavailable. Try again later")
                        (t (or msg "unknown error")))))))
          json)))))

(defun book-gallery--isbn-lookup (isbn)
  "Look up ISBN via Google Books API. Returns plist (:title :author :pages :cover)."
  (let ((isbn (string-trim isbn)))
    (unless (string-match-p "^[0-9Xx-]+$" isbn)
      (user-error "Invalid ISBN format: %s" isbn))
    (let ((clean-isbn (replace-regexp-in-string "-" "" isbn)))
      (unless (or (= (length clean-isbn) 10) (= (length clean-isbn) 13))
        (user-error "ISBN must be 10 or 13 digits, got %d: %s" (length clean-isbn) isbn))
      (condition-case err
          (let* ((data (book-gallery--isbn-fetch-json
                        (format "https://www.googleapis.com/books/v1/volumes?q=isbn:%s&key=%s"
                                clean-isbn book-gallery-google-books-api-key)))
                 (total (cdr (assq 'totalItems data)))
                 (items (cdr (assq 'items data)))
                 (vol (when (and items (> (length items) 0))
                        (cdr (assq 'volumeInfo (aref items 0)))))
                 (title (cdr (assq 'title vol)))
                 (authors (cdr (assq 'authors vol)))
                 (author (when (and authors (> (length authors) 0))
                           (aref authors 0)))
                 (pages (cdr (assq 'pageCount vol)))
                 (image-links (cdr (assq 'imageLinks vol)))
                 (cover (or (cdr (assq 'thumbnail image-links)) "")))
            (cond
             ((and (numberp total) (= total 0))
              (message "No books found for ISBN %s. The edition may not be in Google's database" clean-isbn) nil)
             ((null title)
              (message "ISBN %s found but missing title data" clean-isbn) nil)
             (t
              (when (= (or pages 0) 0)
                (message "Warning: no page count for ISBN %s" clean-isbn))
              (when (string-empty-p cover)
                (message "Warning: no cover image for ISBN %s" clean-isbn))
              (list :title title
                    :author (or author "Unknown")
                    :pages (or pages 0)
                    :cover (replace-regexp-in-string "http://" "https://" cover)))))
        (user-error (signal (car err) (cdr err)))
        (error
         (message "ISBN lookup failed: %s" (error-message-string err))
         nil)))))

(defun book-gallery-new-from-isbn ()
  "Create a new book by looking up an ISBN."
  (interactive)
  (let* ((isbn (read-string "ISBN: "))
         (data (book-gallery--isbn-lookup isbn)))
    (if (null data)
        (message "Could not find book for ISBN %s" isbn)
      (let* ((title (plist-get data :title))
             (author (plist-get data :author))
             (pages (plist-get data :pages))
             (cover (plist-get data :cover))
             (slug (replace-regexp-in-string "[^a-z0-9]+" "_" (downcase title)))
             (fname (format "%s-%s.org"
                            (format-time-string "%Y%m%d%H%M%S")
                            slug))
             (fpath (expand-file-name fname org-roam-directory)))
        (with-temp-file fpath
          (insert (format ":PROPERTIES:\n:ID:       %s\n:AUTHOR:   %s\n:ISBN:     %s\n:COVER:    [[%s]]\n:RATING:   0\n:PAGES_READ: 0\n:TOTAL_PAGES: %d\n:END:\n#+title: %s\n#+filetags: :book:planned:\n\n* Read log\n:LOGBOOK:\n:END:\n"
                          (org-id-new) author isbn cover pages title)))
        (org-roam-db-update-file fpath)
        (message "Created: %s by %s (%d pages)" title author pages)
        (book-gallery-refresh)))))

(defun book-gallery-fill-from-isbn ()
  "Fill missing metadata on the book at point from ISBN lookup."
  (interactive)
  (when-let ((file (get-text-property (point) 'book-file)))
    (let* ((isbn (read-string "ISBN: "))
           (data (book-gallery--isbn-lookup isbn)))
      (if (null data)
          (message "Could not find book for ISBN %s" isbn)
        (with-current-buffer (find-file-noselect file)
          (save-excursion
            ;; Store ISBN if missing
            (goto-char (point-min))
            (unless (re-search-forward "^:ISBN:" nil t)
              (goto-char (point-min))
              (when (re-search-forward "^:AUTHOR:.*$" nil t)
                (end-of-line)
                (insert (format "\n:ISBN:     %s" isbn))))
            ;; Update author if empty
            (goto-char (point-min))
            (when (re-search-forward "^:AUTHOR: *$" nil t)
              (replace-match (format ":AUTHOR:   %s" (plist-get data :author)) t t))
            ;; Update cover if missing
            (goto-char (point-min))
            (unless (re-search-forward "^:COVER:" nil t)
              (goto-char (point-min))
              (when (re-search-forward "^:AUTHOR:.*$" nil t)
                (end-of-line)
                (insert (format "\n:COVER:    [[%s]]" (plist-get data :cover)))))
            ;; Update total pages if 0
            (goto-char (point-min))
            (when (re-search-forward "^:TOTAL_PAGES: +0$" nil t)
              (replace-match (format ":TOTAL_PAGES: %d" (plist-get data :pages)) t t))
            (save-buffer)))
        (message "Updated from ISBN: %s" (plist-get data :title))
        (book-gallery-refresh)))))


(defun book-gallery--set-status (new-status)
  "Set the status of the book at point to NEW-STATUS."
  (when-let ((file (get-text-property (point) 'book-file)))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^#\\+filetags:.*$" nil t)
          (let* ((line (match-string 0))
                 (current (seq-find (lambda (s) (string-match-p (concat ":" s ":") line))
                                    '("planned" "active" "finished"))))
            (when current
              (replace-match
               (replace-regexp-in-string (concat ":" current ":") (concat ":" new-status ":") line)
               t t)
              (save-buffer)
              (org-roam-db-update-file file))))))
    (message "Status → %s" new-status)
    (book-gallery-refresh)))

(defun book-gallery-mark-done ()
  "Mark book at point as finished, set pages_read = total_pages."
  (interactive)
  (when-let ((file (get-text-property (point) 'book-file)))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^:TOTAL_PAGES: +\\([0-9]+\\)" nil t)
          (let ((total (match-string 1)))
            (goto-char (point-min))
            (when (re-search-forward "^:PAGES_READ: +\\([0-9]+\\)" nil t)
              (replace-match total nil nil nil 1))))
        (save-buffer)))
    (book-gallery--set-status "finished")))

(defun book-gallery-mark-active ()
  "Mark book at point as active."
  (interactive)
  (book-gallery--set-status "active"))

(defun book-gallery-mark-planned ()
  "Mark book at point as planned."
  (interactive)
  (book-gallery--set-status "planned"))

(defun book-gallery-open-hsplit ()
  "Open the book at point in a horizontal split."
  (interactive)
  (if-let ((file (get-text-property (point) 'book-file)))
      (progn (split-window-below) (other-window 1) (find-file file))
    (message "No book at point")))

(defun book-gallery-open-vsplit ()
  "Open the book at point in a vertical split."
  (interactive)
  (if-let ((file (get-text-property (point) 'book-file)))
      (progn (split-window-right) (other-window 1) (find-file file))
    (message "No book at point")))

(defun book-gallery-set-rating (rating)
  "Set RATING (1-5) on the book at point."
  (interactive "p")
  (when-let ((file (get-text-property (point) 'book-file)))
    (when (<= 1 rating 5)
      (with-current-buffer (find-file-noselect file)
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^:RATING: +\\([0-9]+\\)" nil t)
            (replace-match (number-to-string rating) nil nil nil 1)
            (save-buffer))))
      (book-gallery-refresh))))

(defun book-gallery--update-pages (file pages)
  "Set PAGES_READ in FILE to PAGES."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^:PAGES_READ: +\\([0-9]+\\)" nil t)
        (replace-match (number-to-string pages) nil nil nil 1)
        (save-buffer)))))

(defun book-gallery-set-pages ()
  "Prompt for current page and update PAGES_READ on the book at point."
  (interactive)
  (when-let ((file (get-text-property (point) 'book-file)))
    (let ((page (read-number "Page you're on: ")))
      (book-gallery--update-pages file page)
      (book-gallery-refresh))))

(defun book-gallery-toggle-clock ()
  "Toggle clock on the book at point. Clocks into the Read log heading.
On clock-out, prompts for current page."
  (interactive)
  (when-let ((file (get-text-property (point) 'book-file)))
    (let ((buf (find-file-noselect file)))
      (if (and (org-clocking-p)
               (eq (marker-buffer org-clock-marker) buf))
          ;; Clock out, then ask for page
          (progn
            (with-current-buffer buf
              (save-excursion
                (goto-char org-clock-marker)
                (org-clock-out)))
            (let ((page (read-number "Page you're on: ")))
              (book-gallery--update-pages file page)))
        ;; Clock in to "Read log" heading
        (with-current-buffer buf
          (save-excursion
            (goto-char (point-min))
            (if (re-search-forward "^\\*+ Read log" nil t)
                (org-clock-in)
              (message "No 'Read log' heading found in %s" file))))))
    (book-gallery-refresh)))

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

(defvar book-gallery--filter-title nil)

(defun book-gallery-search ()
  "Filter books by title."
  (interactive)
  (let ((query (read-string "Search title: ")))
    (setq book-gallery--filter-title (if (string-empty-p query) nil query))
    (book-gallery-refresh)))

(defun book-gallery-help ()
  "Show keybinding help."
  (interactive)
  (let ((buf (get-buffer-create "*yako's library help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert
         (propertize "yako's library keybindings\n\n" 'face '(:weight bold :height 1.2))
         (propertize "Navigation\n" 'face '(:weight bold :foreground "#89b4fa"))
         "  j/k        next/prev book\n"
         "  RET        open book\n"
         "  o          open in horizontal split\n"
         "  O          open in vertical split\n\n"
         (propertize "Actions\n" 'face '(:weight bold :foreground "#a6e3a1"))
         "  n          new book\n"
         "  I          new book from ISBN\n"
         "  i          fill metadata from ISBN\n"
         "  c          toggle clock (prompts page on clock-out)\n"
         "  p          set current page\n"
         "  D          mark done (finished + full pages)\n"
         "  A          mark active\n"
         "  P          mark planned\n"
         "  1-5        set rating\n\n"
         (propertize "View\n" 'face '(:weight bold :foreground "#cba6f7"))
         "  /          search by title\n"
         "  SPC m f s  filter by status\n"
         "  SPC m f t  filter by tag\n"
         "  SPC m f a  clear filters\n"
         "  SPC m s t  sort by title\n"
         "  SPC m s a  sort by author\n"
         "  SPC m s r  sort by rating\n"
         "  SPC m s s  sort by status\n"
         "  g r        refresh\n\n"
         (propertize "  q  quit    ?  this help\n" 'face '(:foreground "#6c7086")))
        (special-mode)
        (goto-char (point-min))))
    (pop-to-buffer buf)))

;; Keybinding
(map! :leader :desc "Book gallery" "n b" #'book-gallery)

(provide '+book-gallery)
;;; +book-gallery.el ends here
