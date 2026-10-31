;;; endgame-today-test.el --- tests for +endgame-today.el -*- lexical-binding: t; -*-
;; Runs without Doom, against a throwaway vault:
;; : emacs -Q --batch -L ~/.config/emacs/.local/straight/build-31.1/org -l ~/.config/doom/tests/endgame-today-test.el -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'org)
(require 'org-agenda)
(require 'org-id)
(setq org-id-locations-file (make-temp-file "endgame-today-test-ids"))

(load (expand-file-name "../+endgame-today.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defvar +endgame-today-test-dir nil)

(defconst +endgame-today-test-day "2026-10-31"
  "The day the tests look at, a Saturday.")

(defun +endgame-today-test--file (name text)
  (let ((f (expand-file-name name +endgame-today-test-dir)))
    (make-directory (file-name-directory f) t)
    (with-temp-file f (insert text))
    f))

(defmacro +endgame-today-test--with-vault (&rest body)
  "Run BODY in a throwaway vault, with org's today on `+endgame-today-test-day'."
  (declare (indent 0))
  `(let* ((+endgame-today-test-dir (file-name-as-directory (make-temp-file "endgame-today-test" t)))
          (org-directory +endgame-today-test-dir)
          (org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "STRT(s!)" "|" "DONE(d!)" "KILL(k@)")
                               (sequence "APPT(a)" "|" "DONE(d!)")))
          (org-log-into-drawer t)
          (org-log-done 'time)
          (org-extend-today-until 5)
          (org-id-track-globally nil)
          (org-agenda-files nil)
          (sat (+endgame-today--abs +endgame-today-test-day))
          (+endgame-today--areas-cache nil)
          (+endgame-today--slow-cache nil))
     (+endgame-today-test--file
      "roam/daily/week44-2026-10-26.org"
      (concat
       ":PROPERTIES:\n:ID:       week44\n:END:\n#+title: Week 44 2026 (2026-10-26)\n"
       "#+filetags: :journal:weekly:\n\n"
       "#+BEGIN: clocktable :scope agenda :block 2026-W44\n| a | table |\n#+END:\n\n"
       "Ship the today panel.\nNothing else matters.\n\n"
       "* Friday, 2026-10-30 :daily:\n:PROPERTIES:\n:ID:       fri\n:END:\n"
       "** DO list [0/1]\n"
       "*** TODO Morning routine\n:PROPERTIES:\n:ROUTINE:  Morning routine\n:END:\n<2026-10-30 Fri 09:00>\n"
       "* Saturday, 2026-10-31 :daily:\n:PROPERTIES:\n:ID:       sat\n:END:\n"
       "** DO list [1/5]\n"
       "*** TODO piano\nSCHEDULED: <2026-10-31 Sat>\n:PROPERTIES:\n:ID:       copy-piano\n:HABIT_ID: src-piano\n:STYLE:    habit\n:END:\n"
       "*** DONE read\nCLOSED: [2026-10-31 Sat 09:30] SCHEDULED: <2026-10-31 Sat>\n"
       ":PROPERTIES:\n:ID:       copy-read\n:HABIT_ID: src-read\n:STYLE:    habit\n:END:\n"
       "*** TODO learning session [0/3] :learning:\n<2026-10-31 Sat 16:00-18:00>\n"
       ":PROPERTIES:\n:ROUTINE:  Session routine\n:AREA:     learning\n:END:\n"
       "- [ ] Start\n- [ ] During\n- [ ] End\n"
       "*** TODO Full Shutdown routine [0/1]\n:PROPERTIES:\n:ROUTINE:  Full Shutdown routine\n:END:\n"
       "<2026-10-31 Sat 21:30>\n- [ ] tea\n"
       "*** TODO breakfast\n"
       "** 10:00 a journal entry\nprose, not a task\n"))
     (+endgame-today-test--file
      "roam/life.org"
      (concat
       "#+title: life\n\n* Appointments\n"
       "** APPT barber\n<2026-10-31 Sat 14:00-14:45>\n"
       "** APPT dentist\n<2026-11-02 Mon 10:00>\n"
       "* Errands\n"
       "** TODO copy room keys\nSCHEDULED: <2026-10-28 Wed>\n"
       "** DONE post the letter\nCLOSED: [2026-10-31 Sat 11:00] SCHEDULED: <2026-10-29 Thu>\n"
       "** DONE old errand\nCLOSED: [2026-10-31 Sat 12:00]\n"))
     (+endgame-today-test--file
      "roam/project.org"
      (concat
       "#+title: project\n\n"
       "* TODO write the chapter\nDEADLINE: <2026-11-03 Tue>\n"
       ":LOGBOOK:\n"
       "CLOCK: [2026-10-31 Sat 10:00]--[2026-10-31 Sat 11:12] =>  1:12\n"
       "CLOCK: [2026-10-30 Fri 23:00]--[2026-10-31 Sat 00:30] =>  1:30\n"
       "CLOCK: [2026-11-01 Sun 01:00]--[2026-11-01 Sun 02:00] =>  1:00\n"
       ":END:\n"
       "* TODO later\nSCHEDULED: <2026-11-02 Mon>\n"))
     (+endgame-today-test--file
      "roam/upcoming.org"
      (concat
       "#+title: upcoming\n\n"
       "* TODO piano session [0/1] :piano:\n:PROPERTIES:\n:ROUTINE:  Session routine\n:AREA:     piano\n:END:\n"
       "<2026-10-31 Sat 09:00-09:30>\n- [ ] play\n"
       "* TODO learning session [0/1] :learning:\n:PROPERTIES:\n:ROUTINE:  Session routine\n:END:\n"
       "<2026-11-02 Mon 16:00-18:00>\n- [ ] Start\n"))
     (+endgame-today-test--file
      "roam/areas.org"
      (concat
       "#+title: areas\n\n* Pursuits category\n"
       "** Learning\n:PROPERTIES:\n:AREA_TAG:      learning\n:END:\n"
       "** Piano\n:PROPERTIES:\n:AREA_TAG:      piano\n:END:\n"))
     (+endgame-today-test--file
      "roam/inbox.org"
      "#+title: inbox\n\n* TODO call mom\n* TODO find the charger\n* DONE done already\n")
     (let ((+endgame-upcoming-file (expand-file-name "roam/upcoming.org" org-directory))
           (+endgame-areas-file (expand-file-name "roam/areas.org" org-directory))
           (+endgame-life-file (expand-file-name "roam/life.org" org-directory))
           (+endgame-inbox-file (expand-file-name "roam/inbox.org" org-directory))
           (org-agenda-files (directory-files-recursively org-directory "\\.org\\'")))
       (cl-letf (((symbol-function 'org-today) (lambda () sat)))
         (unwind-protect (progn ,@body)
           (dolist (buf (buffer-list))
             (let ((f (buffer-file-name buf)))
               (when (and f (string-prefix-p +endgame-today-test-dir f))
                 (with-current-buffer buf (set-buffer-modified-p nil))
                 (kill-buffer buf))))
           (delete-directory +endgame-today-test-dir t))))))

(defvar +endgame-upcoming-file)
(defvar +endgame-areas-file)
(defvar +endgame-life-file)
(defvar +endgame-inbox-file)

(defun +endgame-today-test--titles (items)
  (mapcar (lambda (i) (alist-get 'title i)) items))

(defun +endgame-today-test--item (title items)
  (seq-find (lambda (i) (equal (alist-get 'title i) title)) items))

(ert-deftest +endgame-today-lists-the-day-timed-first ()
  (+endgame-today-test--with-vault
    (let* ((data (+endgame-today-items nil))
           (items (alist-get 'items data)))
      (should (equal (alist-get 'date data) "2026-10-31"))
      ;; timed by start, then open untimed, then done
      (should (equal (+endgame-today-test--titles (seq-take items 4))
                     '("piano session" "barber" "learning session" "Full Shutdown routine")))
      (should (equal (+endgame-today-test--titles (last items 2)) '("read" "post the letter")))
      (should (member "copy room keys" (+endgame-today-test--titles items)))
      (should (member "breakfast" (+endgame-today-test--titles items)))
      ;; another day's, a future one, prose, a closed task that was never planned
      (dolist (gone '("Morning routine" "dentist" "later" "10:00 a journal entry" "old errand"
                      "write the chapter"))
        (should-not (member gone (+endgame-today-test--titles items))))
      (should (equal (alist-get 'counts data) '((done . 2) (total . 9)))))))

(ert-deftest +endgame-today-items-know-what-they-are ()
  (+endgame-today-test--with-vault
    (let ((items (alist-get 'items (+endgame-today-items nil))))
      (cl-flet ((get (title key) (alist-get key (+endgame-today-test--item title items))))
        (should (eq (get "barber" 'kind) 'appt))
        (should (equal (get "barber" 'state) "APPT"))
        (should (equal (list (get "barber" 'start) (get "barber" 'end)) '(840 885)))
        (should (eq (get "piano" 'kind) 'habit))
        (should (equal (get "piano" 'ref) "copy-piano"))
        (should (eq (get "Full Shutdown routine" 'kind) 'routine))
        (should (equal (get "Full Shutdown routine" 'start) 1290))
        (should (equal (get "Full Shutdown routine" 'progress) "[0/1]"))
        ;; staged in upcoming, with its area
        (should (eq (get "piano session" 'kind) 'session))
        (should (equal (get "piano session" 'area) "piano"))
        (should (equal (get "piano session" 'file) "roam/upcoming.org"))
        ;; a timestamp above its drawer: org misses the drawer, the list doesn't
        (should (eq (get "learning session" 'kind) 'session))
        (should (equal (get "learning session" 'area) "learning"))
        (should (eq (get "breakfast" 'kind) 'task))
        (should (string-match-p "\\`roam/daily/week44-2026-10-26.org:[0-9]+\\'" (get "breakfast" 'ref)))
        ;; rollover, with no time of its old day
        (should (equal (get "copy room keys" 'rollover) 3))
        (should-not (get "copy room keys" 'start))
        (should (get "post the letter" 'done))))))

(ert-deftest +endgame-today-deadlines-ahead-are-not-due ()
  (+endgame-today-test--with-vault
    (let ((data (+endgame-today-items nil)))
      (should (equal (+endgame-today-test--titles (alist-get 'ahead data)) '("write the chapter")))
      (should (string-match-p "In 3 d" (alist-get 'agenda (car (alist-get 'ahead data))))))))

(ert-deftest +endgame-today-json-has-the-contract ()
  (+endgame-today-test--with-vault
    (let* ((json-object-type 'alist) (json-array-type 'list) (json-key-type 'symbol)
           (data (json-read-from-string (+endgame-today-json "2026-10-31")))
           (barber (seq-find (lambda (i) (equal (alist-get 'title i) "barber")) (alist-get 'items data))))
      (should (equal (alist-get 'date data) "2026-10-31"))
      (should (equal (alist-get 'counts data) '((done . 2) (total . 9))))
      (dolist (key '(ref title state done kind start end tags area file))
        (should (assq key barber)))
      (should (equal (alist-get 'start barber) "14:00"))
      (should (equal (alist-get 'end barber) "14:45"))
      (should (equal (alist-get 'kind barber) "appt"))
      (should (eq (alist-get 'done barber) :json-false))
      (should (equal (alist-get 'priority (alist-get 'week data)) "Ship the today panel. Nothing else matters."))
      (should (equal (alist-get 'number (alist-get 'week data)) 44))
      (should (equal (alist-get 'inbox_count data) 2))
      (should (equal (mapcar (lambda (i) (alist-get 'title i))
                             (alist-get 'rollovers (alist-get 'watch_out data)))
                     '("copy room keys")))
      (should (equal (alist-get 'total (alist-get 'clocked data)) 132)))))

(ert-deftest +endgame-today-clocked-counts-org-s-day ()
  (+endgame-today-test--with-vault
    ;; Saturday 05:00 to Sunday 05:00: 10:00-11:12 and Sunday's 01:00-02:00,
    ;; not Friday night's clock that ended at 00:30
    (let ((clocked (+endgame-today-clocked "2026-10-31")))
      (should (= (alist-get 'total clocked) 132))
      (should (equal (alist-get 'title (car (alist-get 'headings clocked))) "write the chapter")))))

(ert-deftest +endgame-today-reopens-to-the-state-it-had ()
  (+endgame-today-test--with-vault
    (with-temp-buffer
      (org-mode)
      (insert "* DONE barber\n:LOGBOOK:\n- State \"DONE\"       from \"APPT\"       [2026-10-31 Sat 15:00]\n:END:\n"
              "* DONE errand\n")
      (goto-char (point-min))
      (should (equal (+endgame-today--reopen-state '((kind . appt))) "APPT"))
      (outline-next-heading)
      (should (equal (+endgame-today--reopen-state '((kind . task))) "TODO"))
      (puthash "x" "NEXT" +endgame-today--was)
      (should (equal (+endgame-today--reopen-state '((kind . task) (ref . "x"))) "NEXT"))
      (remhash "x" +endgame-today--was))))

(ert-deftest +endgame-today-dashboard-draws ()
  (+endgame-today-test--with-vault
    (with-current-buffer (+endgame-today-dashboard)
      (unwind-protect
          (progn
            (+endgame-today-refresh)
            (let ((text (buffer-string)))
              (should (string-match-p "\\`TODAY · Sat 31 Oct · W44" text))
              (should (string-match-p "2/9" text))
              (should (string-match-p "Ship the today panel" text))
              (should (string-match-p "\\[ \\] 14:00–14:45 ● barber" text))
              (should (string-match-p "Sched\\. 3x" text))
              (should (string-match-p "WATCH OUT" text))
              (should (string-match-p "CLOCKED  2:12" text)))
            ;; every item line leads somewhere
            (goto-char (point-min))
            (search-forward "barber")
            (should (eq (get-text-property (line-beginning-position) '+endgame-today-action)
                        #'+endgame-today/toggle)))
        (kill-buffer)))))

(ert-deftest +endgame-today-ticks-and-unticks-the-real-heading ()
  (+endgame-today-test--with-vault
    (let ((+endgame-today-save-after-change t))
      (with-current-buffer (+endgame-today-dashboard)
        (unwind-protect
            (cl-flet ((tick ()
                        (+endgame-today-refresh)
                        (goto-char (point-min))
                        (search-forward "barber")
                        (+endgame-today/toggle)
                        (with-current-buffer (find-buffer-visiting +endgame-life-file)
                          (list (buffer-modified-p)
                                (progn (goto-char (point-min))
                                       (re-search-forward "^\\*\\* \\([A-Z]+\\) barber")
                                       (match-string 1))))))
              (should (equal (tick) '(nil "DONE")))
              (should (equal (tick) '(nil "APPT"))))
          (kill-buffer))))))

(ert-deftest +endgame-today-dashboard-watch-out-at-the-bottom ()
  (+endgame-today-test--with-vault
    (with-current-buffer (+endgame-today-dashboard)
      (unwind-protect
          (progn
            (+endgame-today-refresh)
            (let ((text (buffer-string)))
              (should (< (string-match "AREAS" text) (string-match "WATCH OUT" text)))
              (should (< (string-match "WATCH OUT" text) (string-match "RET tick" text)))))
        (kill-buffer)))))

(ert-deftest +endgame-today-note-shows-one-day-and-walks-the-days ()
  (+endgame-today-test--with-vault
    (let* ((win (selected-window))
           (note (+endgame-today--note-show sat win)))
      (unwind-protect
          (with-current-buffer note
            ;; only Saturday's heading, from its first line
            (should (buffer-narrowed-p))
            (should (string-prefix-p "* Saturday, 2026-10-31" (buffer-string)))
            (should-not (string-match-p "Friday" (buffer-string)))
            (should +endgame-today-note-mode)
            (should (string-match-p "◂ H Fri 30 Oct" +endgame-today-note--header))
            (should (string-match-p "Saturday 31 Oct · today · W44 day 6/7 · note 2/2"
                                    +endgame-today-note--header))
            (should (string-match-p "none ▸" +endgame-today-note--header))
            ;; H: Friday, Saturday's indirect buffer is dropped
            (+endgame-today-note/previous)
            (should-not (buffer-live-p note))
            (with-current-buffer (window-buffer win)
              (should (string-prefix-p "* Friday, 2026-10-30" (buffer-string)))
              (should (string-match-p "1d ago" +endgame-today-note--header))
              (should (string-match-p "Sat 31 Oct L ▸" +endgame-today-note--header))
              (should-error (+endgame-today-note/previous) :type 'user-error)
              (+endgame-today-note/next))
            (with-current-buffer (window-buffer win)
              (should (string-prefix-p "* Saturday" (buffer-string)))))
        (with-current-buffer (window-buffer win)
          (when +endgame-today-note-mode (kill-buffer)))))))

(ert-deftest +endgame-today-note-without-a-day-is-a-placeholder ()
  (+endgame-today-test--with-vault
    (let ((buf (+endgame-today--note-buffer (1+ sat))))
      (unwind-protect
          (with-current-buffer buf
            (should-not (buffer-base-buffer))
            (should (string-match-p "No daily note for 2026-11-01" (buffer-string)))
            (should (string-match-p "◂ H Sat 31 Oct" +endgame-today-note--header)))
        (kill-buffer buf)))))

(ert-deftest +endgame-today-timeline-svg-in-theme-colours ()
  (should (equal (+endgame-today--blend "#ffffff" "#000000" 0.5) "#808080"))
  (should-not (+endgame-today--blend "unspecified-bg" "#000000" 0.5))
  (let ((+endgame-today--svg-style
         (list '(((:stroke . "#5b0103") . "#f38ba8") ((:fill . "#ffffff") . "#cdd6f4"))
               11 "Iosevka")))
    (should (equal (+endgame-today--svg-rect-a '(svg 1 2 3 4 :stroke "#5B0103" :fill "#000"))
                   '(svg 1 2 3 4 :stroke "#f38ba8" :fill "#000")))
    (should (equal (+endgame-today--svg-text-a '(svg "hi" :fill "#ffffff" :font-size 14))
                   '(svg "hi" :fill "#cdd6f4" :font-size 11 :font-family "Iosevka"))))
  (let ((+endgame-today--svg-style nil))
    (should (equal (+endgame-today--svg-text-a '(svg "hi" :fill "#ffffff"))
                   '(svg "hi" :fill "#ffffff")))))

;;; endgame-today-test.el ends here
