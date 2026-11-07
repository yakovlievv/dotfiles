;;; sleep-test.el --- tests for +sleep.el -*- lexical-binding: t; -*-
;;
;; Runs without Doom, in a throwaway vault, on the harness of
;; endgame-capture-test.el (the config blocks, `+endgame-capture.el', the
;; vault macro); its own tests are unbound here so they run once, there.
;;
;; emacs -Q --batch -L ~/.config/emacs/.local/straight/build-31.1/org \
;;   -L ~/.config/emacs/.local/straight/build-31.1/org-journal \
;;   -l ~/dotfiles/emacs/tests/sleep-test.el -f ert-run-tests-batch-and-exit

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (load (expand-file-name "endgame-capture-test.el" dir) nil t)
  (dolist (test (ert-select-tests t t))
    (ert-make-test-unbound (ert-test-name test)))
  (load (expand-file-name "../+sleep.el" dir) nil t))

(defconst +sleep-test-source
  (concat "#+title: sleep optimization system\n\n"
          "* Components\n"
          "** Sleep schedule\n:PROPERTIES:\n:ID:       src-sleep\n:END:\n"
          "<2031-01-01 Wed 01:00-09:00 +1d>\nThe default night.\n"
          "** Tools\n")
  "The sleep system note, with the default night.")

(defmacro +sleep-test--with-vault (&rest body)
  "Run BODY in `+endgame-test--with-vault' plus the sleep system note."
  (declare (indent 0))
  `(+endgame-test--with-vault
     (let ((org-extend-today-until 5)
           (+sleep-source-id "src-sleep"))
       (+endgame-test--file "roam/sleep_system.org" +sleep-test-source)
       ,@body)))

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
      ;; a child of the day, after its last child, not in the DO list
      (org-with-point-at m
        (should (= (org-current-level) 2))
        (save-excursion
          (org-up-heading-safe)
          (should (string-match-p "2031-01-07" (org-get-heading t t t t)))))
      (should (string-match-p "\\*\\* 10:00\nprose\n\\*\\* Sleep\n"
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

;;; sleep-test.el ends here
