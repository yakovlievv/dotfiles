;;; sleep-test.el --- tests for +sleep.el -*- lexical-binding: t; -*-
;;
;; Runs without Doom, in a throwaway vault, on the harness of
;; endgame-capture-test.el (the config blocks, `+endgame-capture.el',
;; `+sleep.el', the vault macro with the sleep system note); its own tests
;; are unbound here so they run once, there.
;;
;; emacs -Q --batch -L ~/.config/emacs/.local/straight/build-31.1/org \
;;   -L ~/.config/emacs/.local/straight/build-31.1/org-journal \
;;   -l ~/dotfiles/emacs/tests/sleep-test.el -f ert-run-tests-batch-and-exit

;; that file loads +endgame-capture.el and +sleep.el
(load (expand-file-name "endgame-capture-test.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(dolist (test (ert-select-tests t t))
  (ert-make-test-unbound (ert-test-name test)))

(defmacro +sleep-test--with-vault (&rest body)
  "Run BODY in `+endgame-test--with-vault' (it has the sleep system note)."
  (declare (indent 0))
  `(+endgame-test--with-vault ,@body))

(defun +sleep-test--day (date &optional body)
  "Write a set-up journal day for DATE (its week file) with BODY under it."
  (let ((file (org-journal--get-entry-path (+endgame--date-time date))))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert "#+title: week\n\n"
              (format-time-string "* %A, %Y-%m-%d\n" (+endgame--date-time date))
              ":PROPERTIES:\n:ID:       day-" date "\n:END:\n"
              (or body "** DO list [0/1]\n*** TODO something\n** 10:00\nprose\n")))
    file))

(defun +sleep-test--source-prop (prop)
  (org-entry-get (+sleep--source) prop))

(defun +sleep-test--entry (m)
  "The text of the entry at marker M, its subtree included."
  (org-with-point-at m
    (org-with-wide-buffer
     (buffer-substring-no-properties (point) (save-excursion (org-end-of-subtree t t) (point))))))

(defun +sleep-test--time (date hhmm)
  "DATE (\"YYYY-MM-DD\") at HHMM as an Emacs time."
  (pcase-let ((`(,y ,mo ,d) (mapcar #'string-to-number (split-string date "-")))
              (`(,h ,mi) (mapcar #'string-to-number (split-string hhmm ":"))))
    (encode-time 0 mi h d mo y)))

;;; Task 1: planning a night

(ert-deftest sleep-occurrence-after-midnight ()
  (+sleep-test--with-vault
    (should (equal (+sleep-occurrence-date "2031-01-07") "2031-01-08"))
    (should (equal (+sleep-occurrence-date "2031-01-07" "23:30") "2031-01-07"))
    (should (equal (+sleep-occurrence-date "2031-01-31" "04:59") "2031-02-01"))
    (should (equal (+sleep-occurrence-date "2031-01-07" "05:00") "2031-01-07"))))

(ert-deftest sleep-night-of-time ()
  (let ((org-extend-today-until 5))
    (should (equal (+sleep-night-of-time (+sleep-test--time "2031-01-08" "00:30")) "2031-01-07"))
    (should (equal (+sleep-night-of-time (+sleep-test--time "2031-01-08" "06:00")) "2031-01-08"))
    (should (equal (+sleep-night-of-time (+sleep-test--time "2031-03-01" "04:59")) "2031-02-28"))))

(ert-deftest sleep-plan-into-day ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (should-not (+sleep-copy "2031-01-07"))
    (should-not (+sleep-skipped-p "2031-01-07"))
    (let* ((m (+sleep-plan "2031-01-07"))
           (text (+sleep-test--entry m)))
      (should (equal (+sleep-copy "2031-01-07") m))
      (should (string-match-p "^\\*\\* Sleep\n" text))
      (should-not (org-with-point-at m (org-get-todo-state)))
      (should (equal (org-entry-get m "NIGHT") "2031-01-07"))
      (should (equal (org-entry-get m "SLEEP_ID") "src-sleep"))
      (should (equal (org-entry-get m "AREA") "sleep"))
      (should (org-entry-get m "CALDAV_UID"))
      (should (org-entry-get m "ID"))
      (should (string-match-p "^<2031-01-08 Wed 01:00-09:00>$" text))
      ;; a child of the day, right after its DO list, not in it
      (org-with-point-at m
        (should (= (org-current-level) 2))
        (save-excursion
          (org-up-heading-safe)
          (should (string-match-p "2031-01-07" (org-get-heading t t t t)))))
      (should (string-match-p "\\*\\*\\* TODO something\n\\*\\* Sleep\n\\(?:.*\n\\)*?\\*\\* 10:00\nprose\n\\'"
                              (+endgame-test--read (buffer-file-name (marker-buffer m)))))
      (should (equal (+sleep-test--source-prop "SKIP") "2031-01-08"))
      (should (+sleep-skipped-p "2031-01-07")))))

(ert-deftest sleep-plan-into-upcoming ()
  (+sleep-test--with-vault
    (let* ((m (+sleep-plan "2031-01-07"))
           (text (+sleep-test--entry m)))
      (should (file-equal-p (buffer-file-name (marker-buffer m)) +endgame-upcoming-file))
      (should (string-match-p "\\`\\* Sleep\n" text))
      (should (equal (org-entry-get m "NIGHT") "2031-01-07"))
      (should (equal (org-entry-get m "SLEEP_ID") "src-sleep"))
      (should (equal (org-entry-get m "AREA") "sleep"))
      (should (org-entry-get m "CALDAV_UID"))
      (should (string-match-p "^<2031-01-08 Wed 01:00-09:00>$" text))
      (should (equal (+sleep-copy "2031-01-07") m))
      (should (equal (+sleep-test--source-prop "SKIP") "2031-01-08")))))

(ert-deftest sleep-plan-retime ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (let* ((id (org-entry-get (+sleep-plan "2031-01-07") "ID"))
           (m (+sleep-plan "2031-01-07" "23:30" "08:00")))
      (should (equal (org-entry-get m "ID") id))
      (should (string-match-p "^<2031-01-07 Tue 23:30>--<2031-01-08 Wed 08:00>$" (+sleep-test--entry m)))
      (should-not (string-match-p "01:00-09:00" (+sleep-test--entry m)))
      ;; the default's occurrence only: 2031-01-07 is the night before's
      (should (equal (+sleep-test--source-prop "SKIP") "2031-01-08"))
      ;; one copy, and a plan without times leaves it as it is
      (should (equal (+sleep-plan "2031-01-07") m))
      (should (= 1 (with-current-buffer (marker-buffer m)
                     (count-matches "^\\*+ Sleep$" (point-min) (point-max))))))))

(ert-deftest sleep-plan-json ()
  (+sleep-test--with-vault
    (let ((json (json-parse-string (+sleep-plan-json "2031-01-07" "07:00" "10:00") :object-type 'alist)))
      (should (equal (alist-get 'where json) "upcoming"))
      (should (alist-get 'id json))
      (should (integerp (alist-get 'line json)))
      (should (member "roam/upcoming.org" (append (alist-get 'files json) nil)))
      (should (string-match-p "^<2031-01-07 Tue 07:00-10:00>$"
                              (+endgame-test--read +endgame-upcoming-file)))
      (should-not (buffer-modified-p (find-buffer-visiting +endgame-upcoming-file))))))

(ert-deftest sleep-plan-review-fixes ()
  (+sleep-test--with-vault
    ;; the source note changed on disk under an open buffer: re-read, not clobbered
    (let ((file (expand-file-name "roam/sleep_system.org" +endgame-test-dir)))
      (find-file-noselect file)
      (with-temp-file file
        (insert (replace-regexp-in-string ":ID:       src-sleep\n"
                                          ":ID:       src-sleep\n:SKIP:     2031-01-20\n"
                                          +endgame-test-sleep-source t t)))
      (set-file-times file (time-add nil 10))
      (+sleep-plan "2031-01-07")
      (should (equal (+sleep-test--source-prop "SKIP") "2031-01-08 2031-01-20")))
    ;; END alone retimes; times are padded and checked
    (let ((m (+sleep-plan "2031-01-07" nil "9:30")))
      (should (string-match-p "^<2031-01-08 Wed 01:00-09:30>$" (+sleep-test--entry m))))
    (should-error (+sleep-plan "2031-01-07" "25:00" "09:00"))
    (should-error (+sleep-plan "2031-1-7"))))

;;; Task 2: day making, staging, last night, the morning

(defun +sleep-test--sleep-children (date)
  "How many Sleep headings day DATE's subtree has."
  (let ((day (+endgame--day-marker date)))
    (with-current-buffer (marker-buffer day)
      (org-with-wide-buffer
       (goto-char day)
       (count-matches "^\\*\\* Sleep$" (point) (save-excursion (org-end-of-subtree t t) (point)))))))

(ert-deftest sleep-staged-copy-moves-by-night ()
  (+sleep-test--with-vault
    (let ((id (org-entry-get (+sleep-plan "2031-01-07") "ID")))
      (should (string-match-p "<2031-01-08 Wed 01:00-09:00>" (+endgame-test--read +endgame-upcoming-file)))
      ;; its stamp is on 01-08, but it is night 01-07's
      (+endgame-day-ensure "2031-01-08")
      (should (string-match-p id (+endgame-test--read +endgame-upcoming-file)))
      (should-not (equal (org-entry-get (+sleep-copy "2031-01-08") "ID") id))
      (let ((out (json-parse-string (+endgame-day-ensure "2031-01-07") :object-type 'alist)))
        (should (= (alist-get 'moved out) 1)))
      (should-not (string-match-p id (+endgame-test--read +endgame-upcoming-file)))
      (let ((m (+sleep-copy "2031-01-07")))
        (should (equal (org-entry-get m "ID") id))
        (org-with-point-at m
          (should (= (org-current-level) 2))
          (save-excursion
            (org-up-heading-safe)
            (should (string-match-p "2031-01-07" (org-get-heading t t t t))))))
      (should (= 1 (+sleep-test--sleep-children "2031-01-07")))
      (should (= 1 (+sleep-test--sleep-children "2031-01-08")))
      (should-not (string-match-p "^\\*\\*\\* Sleep"
                                  (+endgame-test--read (buffer-file-name (marker-buffer (+sleep-copy "2031-01-07")))))))))

(ert-deftest sleep-day-creation-copies-default ()
  (+sleep-test--with-vault
    (+endgame-day-ensure "2031-01-07")
    (should (= 1 (+sleep-test--sleep-children "2031-01-07")))
    (should (string-match-p "^<2031-01-08 Wed 01:00-09:00>$" (+sleep-test--entry (+sleep-copy "2031-01-07"))))
    (should (equal (+sleep-test--source-prop "SKIP") "2031-01-08"))
    (+endgame-day-ensure "2031-01-07")
    (should (= 1 (+sleep-test--sleep-children "2031-01-07")))
    ;; everything saved
    (should-not (buffer-modified-p (marker-buffer (+sleep--source))))
    (should-not (buffer-modified-p (marker-buffer (+sleep-copy "2031-01-07"))))))

(ert-deftest sleep-day-creation-skipped-night ()
  (+sleep-test--with-vault
    (org-with-point-at (+sleep--source) (+repeat-skip-add "2031-01-08"))
    (should (+sleep-skipped-p "2031-01-07"))
    (should-not (+sleep-ensure-night "2031-01-07"))
    (+endgame-day-ensure "2031-01-07")
    (should (= 0 (+sleep-test--sleep-children "2031-01-07")))
    (should-not (+sleep-copy "2031-01-07"))))

(ert-deftest sleep-log-night-writes-clock ()
  (+sleep-test--with-vault
    (should-not (+sleep-night-logged-p "2031-01-07"))
    (+sleep-log-night "2031-01-07" "2031-01-07 23:30" "2031-01-08 07:10")
    (let ((text (+sleep-test--entry (+sleep-copy "2031-01-07"))))
      (should (string-match-p (concat ":LOGBOOK:\nCLOCK: \\[2031-01-07 Tue 23:30\\]--\\[2031-01-08 Wed 07:10\\] =>  7:40\n:END:\n")
                              text))
      ;; the planned stamp is still the entry's
      (should (string-match-p "^<2031-01-08 Wed 01:00-09:00>$" text)))
    (should (+sleep-night-logged-p "2031-01-07"))
    (should-not (+sleep-night-logged-p "2031-01-06"))
    (should-not (string-match-p "SLEEP_TIME" (+endgame-test--read +endgame-upcoming-file)))
    (should-error (+sleep-log-night "2031-01-07" "2031-01-08 09:00" "2031-01-08 07:00"))))

(ert-deftest sleep-put-morning ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (+sleep-put-morning "2031-01-07" '(3 "7" 6 "  slept ok  "))
    (let ((m (+sleep-copy "2031-01-07")))
      (should (equal (org-entry-get m "MORNING_HEADACHE") "3"))
      (should (equal (org-entry-get m "MORNING_FRESHNESS") "7"))
      (should (equal (org-entry-get m "MORNING_MOOD") "6"))
      (should-not (org-entry-get m "MORNING_NOTES"))
      (should (string-match-p ">\nslept ok\n\\'" (+sleep-test--entry m))))
    (should-error (+sleep-put-morning "2031-01-07" '(5 11 5 nil)))
    (should (equal (org-entry-get (+sleep-copy "2031-01-07") "MORNING_FRESHNESS") "7"))))

(ert-deftest sleep-day-init-asks-last-night-only-when-not-logged ()
  (+sleep-test--with-vault
    (let (asked)
      (add-hook 'org-journal-after-entry-create-hook #'+org-journal-init-day)
      (unwind-protect
          (+endgame-test--answering (list "23:30" "7:10" "3" "7" "6" "fine")
            (cl-letf (((symbol-function 'y-or-n-p) (lambda (p) (push p asked) t)))
              (save-window-excursion
                (org-journal-new-entry nil (+endgame--date-time "2031-01-08")))))
        (remove-hook 'org-journal-after-entry-create-hook #'+org-journal-init-day))
      (should (equal (reverse asked) '("Log last night? " "Log morning? ")))
      (let ((text (+sleep-test--entry (+sleep-copy "2031-01-07"))))
        (should (string-match-p "CLOCK: \\[2031-01-07 Tue 23:30\\]--\\[2031-01-08 Wed 07:10\\] =>  7:40" text))
        (should (string-match-p ":MORNING_MOOD: +6" text))
        (should (string-match-p "\nfine\n" text)))
      ;; the new day has its own night
      (should (= 1 (+sleep-test--sleep-children "2031-01-08")))
      ;; a bed time after midnight is on the next date
      (should (equal (+endgame-test--answering (list "1:15" "9:00")
                       (+sleep--read-night "2031-01-08"))
                     '("2031-01-09 01:15" "2031-01-09 09:00"))))
    ;; last night logged: only the morning is asked
    (let (asked)
      (+sleep-log-night "2031-01-12" "2031-01-13 01:00" "2031-01-13 08:00")
      ;; the next week: in tests org-journal leaves a blank time entry
      ;; ("** ") at the end of a future day, and glues the next day's
      ;; heading onto it
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (p) (push p asked) nil)))
        (+endgame--create-day (+endgame--date-time "2031-01-13") t))
      (should (equal asked '("Log morning? "))))))

;;; Task 3: clock in and out, the next night

(defun +sleep-test--json (string)
  (json-parse-string string :object-type 'alist :array-type 'list :null-object nil :false-object :false))

(defun +sleep-test--copy-text (night)
  (+sleep-test--entry (+sleep-copy night)))

(ert-deftest sleep-clock-in-after-midnight ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (let ((out (+sleep-test--json (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:30")))))
      (should (equal (alist-get 'state out) "in"))
      (should (equal (alist-get 'night out) "2031-01-07"))
      (should (equal (alist-get 'id out) (org-entry-get (+sleep-copy "2031-01-07") "ID")))
      (should (null (alist-get 'closed out)))
      (should (alist-get 'files out)))
    (should (string-match-p "^CLOCK: \\[2031-01-08 Wed 00:30\\]$" (+sleep-test--copy-text "2031-01-07")))
    ;; the calendar day's night isn't touched
    (should-not (+endgame--day-marker "2031-01-08"))
    (should-not (+sleep-copy "2031-01-08"))
    (should-not (buffer-modified-p (marker-buffer (+sleep-copy "2031-01-07"))))))

(ert-deftest sleep-clock-in-closes-other-clock ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (+endgame-test--file "roam/life.org"
                         (concat "#+title: life\n\n* Appointments\n* Errands\n** TODO write the essay\n"
                                 ":LOGBOOK:\nCLOCK: [2031-01-07 Tue 22:00]\nCLOCK: [2031-01-06 Mon 10:00]--[2031-01-06 Mon 11:00] =>  1:00\n:END:\n"))
    (let ((out (+sleep-test--json (+sleep-clock-in-json (+sleep-test--time "2031-01-07" "23:00")))))
      (should (equal (alist-get 'state out) "in"))
      (should (equal (alist-get 'closed out)
                     '(((file . "roam/life.org") (heading . "write the essay")))))
      (should (member "roam/life.org" (alist-get 'files out))))
    (let ((life (+endgame-test--read (expand-file-name "roam/life.org" +endgame-test-dir))))
      (should (string-match-p "^CLOCK: \\[2031-01-07 Tue 22:00\\]--\\[2031-01-07 Tue 23:00\\] =>  1:00$" life))
      (should (string-match-p "^CLOCK: \\[2031-01-06 Mon 10:00\\]--\\[2031-01-06 Mon 11:00\\] =>  1:00$" life)))
    (should (string-match-p "^CLOCK: \\[2031-01-07 Tue 23:00\\]$" (+sleep-test--copy-text "2031-01-07")))))

(ert-deftest sleep-clock-in-twice ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:30"))
    (let* ((file (buffer-file-name (marker-buffer (+sleep-copy "2031-01-07"))))
           (before (+endgame-test--read file))
           (out (+sleep-test--json (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:40")))))
      (should (equal (alist-get 'state out) "already"))
      (should (equal (alist-get 'night out) "2031-01-07"))
      (should (null (alist-get 'files out)))
      (should (equal (+endgame-test--read file) before)))))

(ert-deftest sleep-clock-in-makes-day ()
  (+sleep-test--with-vault
    (should-not (+endgame--day-marker "2031-01-07"))
    (let ((out (+sleep-test--json (+sleep-clock-in-json (+sleep-test--time "2031-01-07" "22:00")))))
      (should (equal (alist-get 'state out) "in"))
      (should (equal (alist-get 'night out) "2031-01-07")))
    (let ((day (+endgame--day-marker "2031-01-07")))
      (should (org-entry-get day "ID"))
      (should (= 1 (+sleep-test--sleep-children "2031-01-07"))))
    (should (string-match-p "^CLOCK: \\[2031-01-07 Tue 22:00\\]$" (+sleep-test--copy-text "2031-01-07")))))

(ert-deftest sleep-clock-in-on-a-skipped-night ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (org-with-point-at (+sleep--source) (+repeat-skip-add "2031-01-08") (save-buffer))
    (+sleep-clock-in-json (+sleep-test--time "2031-01-07" "23:00"))
    (should (string-match-p "^CLOCK: \\[2031-01-07 Tue 23:00\\]$" (+sleep-test--copy-text "2031-01-07")))))

(ert-deftest sleep-clock-out ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:30"))
    (let ((out (+sleep-test--json (+sleep-clock-out-json (+sleep-test--time "2031-01-08" "08:45")))))
      (should (equal (alist-get 'state out) "out"))
      (should (equal (alist-get 'night out) "2031-01-07"))
      (should (equal (alist-get 'id out) (org-entry-get (+sleep-copy "2031-01-07") "ID")))
      (should (equal (alist-get 'minutes out) 495))
      (should (alist-get 'files out)))
    (should (string-match-p "^CLOCK: \\[2031-01-08 Wed 00:30\\]--\\[2031-01-08 Wed 08:45\\] =>  8:15$"
                            (+sleep-test--copy-text "2031-01-07")))
    (should (+sleep-night-logged-p "2031-01-07"))
    (let ((out (+sleep-test--json (+sleep-clock-out-json (+sleep-test--time "2031-01-08" "09:00")))))
      (should (equal (alist-get 'state out) "none"))
      (should (null (alist-get 'night out)))
      (should (null (alist-get 'minutes out)))
      (should (null (alist-get 'files out))))))

(ert-deftest sleep-next-before-wake ()
  (+sleep-test--with-vault
    (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "06:00")))))
      (should (equal (alist-get 'night out) "2031-01-07"))
      (should (equal (alist-get 'bed out) "2031-01-08 01:00"))
      (should (equal (alist-get 'wake out) "2031-01-08 09:00"))
      (should (eq (alist-get 'clockedIn out) :false)))
    ;; at 00:30 the night of the 7th hasn't started: still the 7th
    (should (equal (alist-get 'night (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "00:30"))))
                   "2031-01-07"))))

(ert-deftest sleep-next-after-wake ()
  (+sleep-test--with-vault
    (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "10:00")))))
      (should (equal (alist-get 'night out) "2031-01-08"))
      (should (equal (alist-get 'bed out) "2031-01-09 01:00"))
      (should (equal (alist-get 'wake out) "2031-01-09 09:00")))))

(ert-deftest sleep-next-skipped ()
  (+sleep-test--with-vault
    (org-with-point-at (+sleep--source) (+repeat-skip-add "2031-01-09") (save-buffer))
    (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "10:00")))))
      (should (equal (alist-get 'night out) "2031-01-08"))
      (should (assq 'bed out))
      (should (null (alist-get 'bed out)))
      (should (null (alist-get 'wake out))))))

(ert-deftest sleep-next-moved ()
  (+sleep-test--with-vault
    (org-with-point-at (+sleep--source) (+repeat-skip-add "2031-01-09") (save-buffer))
    ;; a copy moved to the morning of the 9th, hand-made like the calendar would
    (with-current-buffer (find-file-noselect +endgame-upcoming-file)
      (goto-char (point-max))
      (insert "* Sleep\n:PROPERTIES:\n:ID:       moved\n:SLEEP_ID: src-sleep\n:NIGHT:    2031-01-08\n"
              ":AREA:     sleep\n:CALDAV_UID: u\n:END:\n<2031-01-09 Thu 07:00-10:00>\n")
      (save-buffer))
    (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "10:00")))))
      (should (equal (alist-get 'night out) "2031-01-08"))
      (should (equal (alist-get 'bed out) "2031-01-09 07:00"))
      (should (equal (alist-get 'wake out) "2031-01-09 10:00")))
    ;; a copy across midnight
    (+sleep-plan "2031-01-10" "23:30" "08:00")
    (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-10" "12:00")))))
      (should (equal (alist-get 'bed out) "2031-01-10 23:30"))
      (should (equal (alist-get 'wake out) "2031-01-11 08:00")))))

(ert-deftest sleep-next-clocked-in ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:30"))
    (should (eq t (alist-get 'clockedIn (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "01:00"))))))
    (+sleep-clock-out-json (+sleep-test--time "2031-01-08" "08:45"))
    (should (eq :false (alist-get 'clockedIn (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "09:00"))))))))

;;; sleep-test.el ends here
