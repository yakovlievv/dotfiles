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
           (before (+sleep-test--disk file))
           (raw (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:40")))
           (out (+sleep-test--json raw)))
      (should (equal (alist-get 'state out) "already"))
      (should (equal (alist-get 'night out) "2031-01-07"))
      (should (string-match-p "\"files\":\\[\\]" raw))
      (should (equal (+sleep-test--disk file) before)))))

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
    ;; night 01-08 moved to 03:00-10:00: on the morning of the 9th
    (+sleep-plan "2031-01-08" "03:00" "10:00")
    (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "10:00")))))
      (should (equal (alist-get 'night out) "2031-01-08"))
      (should (equal (alist-get 'bed out) "2031-01-09 03:00"))
      (should (equal (alist-get 'wake out) "2031-01-09 10:00")))
    ;; a copy across midnight
    (+sleep-plan "2031-01-10" "23:30" "08:00")
    (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-10" "12:00")))))
      (should (equal (alist-get 'bed out) "2031-01-10 23:30"))
      (should (equal (alist-get 'wake out) "2031-01-11 08:00")))))

(ert-deftest sleep-next-deleted-copy ()
  (+sleep-test--with-vault
    (let* ((m (+sleep-plan "2031-01-08"))
           (id (org-entry-get m "ID")))
      ;; the event deleted on the phone: the stamp goes inactive
      (with-current-buffer (marker-buffer m)
        (org-with-wide-buffer
         (goto-char m)
         (re-search-forward "<\\(2031-01-09 Thu 01:00-09:00\\)>")
         (replace-match "[\\1]")
         (save-buffer)))
      (should (+sleep-skipped-p "2031-01-08"))
      (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "10:00")))))
        (should (equal (alist-get 'night out) "2031-01-08"))
        (should (null (alist-get 'bed out)))
        (should (null (alist-get 'wake out))))
      ;; making the day keeps it cancelled
      (+endgame-day-ensure "2031-01-08")
      (should (+sleep-cancelled-p (+sleep-copy "2031-01-08")))
      ;; planning it again: the same copy, active again
      (let ((again (+sleep-plan "2031-01-08" "02:00" "09:30")))
        (should (equal (org-entry-get again "ID") id))
        (should (= 1 (+sleep-test--sleep-children "2031-01-08")))
        (let ((text (+sleep-test--entry again)))
          (should (string-match-p "^<2031-01-09 Thu 02:00-09:30>$" text))
          (should-not (string-match-p "\\[2031-01-09 Thu 01:00-09:00\\]" text))))
      (should (equal (alist-get 'wake (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "10:00"))))
                     "2031-01-09 09:30")))))

(ert-deftest sleep-next-clocked-in ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:30"))
    (should (eq t (alist-get 'clockedIn (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "01:00"))))))
    (+sleep-clock-out-json (+sleep-test--time "2031-01-08" "08:45"))
    (should (eq :false (alist-get 'clockedIn (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "09:00"))))))))

;;; Task 4: Emacs after the server, sleep as an area

(ert-deftest sleep-resync-drops-stale-clock ()
  (+sleep-test--with-vault
    (let* ((file (+endgame-test--file "roam/life.org"
                                      "#+title: life\n\n* Appointments\n* Errands\n** TODO write the essay\n"))
           (buf (find-file-noselect file)))
      (unwind-protect
          (progn
            (with-current-buffer buf
              (goto-char (point-min))
              (re-search-forward "^\\*\\* TODO write the essay")
              (org-clock-in)
              (save-buffer))
            (should (org-clocking-p))
            ;; the server closes that clock on disk
            (let ((closed (with-current-buffer buf
                            (replace-regexp-in-string
                             "^\\(CLOCK: \\[[^]]*\\]\\)$" "\\1--[2031-01-07 Tue 23:00] =>  1:00"
                             (buffer-string) t))))
              (with-temp-file file (insert closed))
              (set-file-times file (time-add nil 10))
              (+sleep--resync)
              (should-not (org-clocking-p))
              (should-not org-clock-start-time)
              (should-not (buffer-modified-p buf))
              (should (equal (+endgame-test--read file) closed))
              (should (equal (with-current-buffer buf (buffer-string)) closed))))
        (when (org-clocking-p) (+sleep--forget-clock))))))

(ert-deftest sleep-resync-keeps-a-running-clock ()
  (+sleep-test--with-vault
    (let* ((file (+endgame-test--file "roam/life.org" "#+title: life\n\n* Errands\n** TODO write\n"))
           (buf (find-file-noselect file)))
      (unwind-protect
          (progn
            (with-current-buffer buf
              (goto-char (point-min))
              (re-search-forward "^\\*\\* TODO write")
              (org-clock-in)
              (save-buffer))
            (+sleep--resync)
            (should (org-clocking-p)))
        (when (org-clocking-p) (+sleep--forget-clock))))))

(ert-deftest area-sources-prop ()
  (+sleep-test--with-vault
    (+endgame-test--file "roam/areas.org"
                         (concat "#+title: areas\n\n* Health category\n"
                                 "** Sleep\n:PROPERTIES:\n:AREA_TAG:      sleep\n:SOURCES:       prop:SLEEP_ID\n:END:\n"))
    (+endgame-day-ensure "2031-01-07")
    (+endgame-day-ensure "2031-01-08")
    (+endgame--saving
      (+sleep-log-night "2031-01-07" "2031-01-07 23:30" "2031-01-08 07:10"))
    (let ((sources (+endgame-area-sources "sleep"))
          (week (buffer-file-name (marker-buffer (+endgame--day-marker "2031-01-07")))))
      (should (equal (sort (copy-sequence sources) (lambda (a b) (string< (cdr a) (cdr b))))
                     (sort (list (cons week (org-entry-get (+sleep-copy "2031-01-07") "ID"))
                                 (cons week (org-entry-get (+sleep-copy "2031-01-08") "ID")))
                           (lambda (a b) (string< (cdr a) (cdr b)))))))
    ;; a day runs 05:00 to 05:00 (`org-extend-today-until'), as day clocktables count it
    (should (equal (+endgame-area-clocked "sleep" "2031-01-07") 330))
    (should (equal (+endgame-area-clocked "sleep" "2031-01-08") 130))
    (should (equal (+endgame-area-clocked "sleep" "2031-01-07" "2031-01-08") 460))))

;;; From the reviews

(defun +sleep-test--disk (file)
  "FILE's text on disk, not in its buffer."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest sleep-day-ensure-again-writes-once ()
  (+sleep-test--with-vault
    (dotimes (_ 2)
      (+endgame-day-ensure "2031-01-08" '("2031-01-07 23:30" "2031-01-08 07:10") '(3 7 6 "ok")))
    (let ((text (+sleep-test--copy-text "2031-01-07")))
      (should (= 1 (with-temp-buffer (insert text) (count-matches "^CLOCK:" (point-min) (point-max)))))
      (should (= 1 (with-temp-buffer (insert text) (count-matches "^ok$" (point-min) (point-max))))))))

(ert-deftest sleep-log-night-closes-an-open-clock ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:30"))
    (+sleep-log-night "2031-01-07" "2031-01-08 00:30" "2031-01-08 08:00")
    (let ((text (+sleep-test--copy-text "2031-01-07")))
      (should (string-match-p "^CLOCK: \\[2031-01-08 Wed 00:30\\]--\\[2031-01-08 Wed 08:00\\] =>  7:30$" text))
      (should-not (string-match-p "^CLOCK: \\[[^]]*\\]$" text)))
    (should (equal (alist-get 'state (+sleep-test--json (+sleep-clock-out-json (+sleep-test--time "2031-01-08" "09:00"))))
                   "none"))))

(ert-deftest sleep-missing-source-still-makes-the-day ()
  (+sleep-test--with-vault
    (let ((+sleep-source-id "nope"))
      (should (equal (alist-get 'created (+sleep-test--json (+endgame-day-ensure "2031-01-07"))) t))
      (should (org-entry-get (+endgame--day-marker "2031-01-07") "ID")))))

(ert-deftest sleep-interactive-last-night-is-saved ()
  (+sleep-test--with-vault
    (+endgame-test--answering (list "23:30" "7:10")
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (p) (equal p "Log last night? "))))
        (+endgame--create-day (+endgame--date-time "2031-01-08") t)))
    (should (string-match-p "CLOCK: \\[2031-01-07 Tue 23:30\\]" (+sleep-test--disk +endgame-upcoming-file)))
    (should (string-match-p ":SKIP: +2031-01-08 2031-01-09"
                            (+sleep-test--disk (expand-file-name "roam/sleep_system.org" +endgame-test-dir))))))

(ert-deftest sleep-skip-pruning-moves-the-default-on ()
  (+sleep-test--with-vault
    (let ((today (+endgame--today)))
      (org-with-point-at (+sleep--source)
        (+repeat-skip-add "2020-01-02")
        (re-search-forward "<2031-01-01 Wed")
        (replace-match "<2020-01-01 Wed" t t))
      (+sleep-plan today)
      (let ((src (+sleep-test--entry (+sleep--source)))
            (cut (+sleep--add-days today (- +sleep-skip-keep-days))))
        (should-not (string-match-p "2020-01-02" src))
        (should (string-match-p (concat "^<" cut " [A-Z][a-z]+ 01:00-09:00 \\+1d>$") src))
        (should (string-match-p (concat ":SKIP: +" (+sleep-occurrence-date today)) src))))))

(ert-deftest sleep-clock-in-again-after-five ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "04:50"))
    (let ((raw (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "05:10"))))
      (should (string-match-p "\"state\":\"already\"" raw))
      (should (string-match-p "\"night\":\"2031-01-07\"" raw))
      (should (string-match-p "\"closed\":\\[\\]" raw))
      (should (string-match-p "\"files\":\\[\\]" raw)))
    (should-not (+endgame--day-marker "2031-01-08"))))

(ert-deftest sleep-clock-in-saves-a-dirty-buffer-and-any-buffer ()
  (+sleep-test--with-vault
    (let ((file (+sleep-test--day "2031-01-07")))
      ;; an earlier call left the week buffer unsaved
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max))
        (insert "left over\n"))
      ;; called from a buffer whose syntax table doesn't count newline as whitespace
      (with-temp-buffer
        (lisp-interaction-mode)
        (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:30")))
      (should (string-match-p "^CLOCK: \\[2031-01-08 Wed 00:30\\]$" (+sleep-test--disk file)))
      (should-not (buffer-modified-p (find-buffer-visiting file))))))

(ert-deftest sleep-clock-in-leaves-example-clocks ()
  (+sleep-test--with-vault
    (+sleep-test--day "2031-01-07")
    (let ((note (+endgame-test--file "roam/org_syntax.org"
                                     "#+title: org syntax\n\n* Clocks\n#+begin_example\nCLOCK: [2020-01-01 Wed 10:00]\n#+end_example\n")))
      (let ((raw (+sleep-clock-in-json (+sleep-test--time "2031-01-08" "00:30"))))
        (should (string-match-p "\"closed\":\\[\\]" raw)))
      (should (string-match-p "^CLOCK: \\[2020-01-01 Wed 10:00\\]$" (+sleep-test--disk note))))))

(ert-deftest sleep-next-odd-stamps ()
  (+sleep-test--with-vault
    (with-current-buffer (find-file-noselect +endgame-upcoming-file)
      (goto-char (point-max))
      (insert "* Sleep\n:PROPERTIES:\n:ID:       odd\n:SLEEP_ID: src-sleep\n:NIGHT:    2031-01-08\n:END:\n"
              "<2031-01-08 Wed 23:00-07:00>\n"
              "* Sleep\n:PROPERTIES:\n:ID:       notime\n:SLEEP_ID: src-sleep\n:NIGHT:    2031-01-09\n:END:\n"
              "<2031-01-10 Fri>\n")
      (save-buffer))
    (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-08" "12:00")))))
      (should (equal (alist-get 'bed out) "2031-01-08 23:00"))
      (should (equal (alist-get 'wake out) "2031-01-09 07:00")))
    (let ((out (+sleep-test--json (+sleep-next-json (+sleep-test--time "2031-01-09" "12:00")))))
      (should (equal (alist-get 'bed out) "2031-01-10 01:00"))
      (should (equal (alist-get 'wake out) "2031-01-10 09:00")))))

;;; sleep-test.el ends here
