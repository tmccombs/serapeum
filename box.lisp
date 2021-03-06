(in-package #:serapeum)

(declaim (inline box))                  ;Allow dynamic-extent.
(defstruct (box (:constructor box (value))
                (:predicate boxp))
  "A box is just a mutable cell.

You create a box using `box' and get and set its value using the
accessor `unbox'.

    (def a-box (box t))
    (unbox a-box) => t
    (setf (unbox a-box) nil)
    (unbox a-box) => nil

At the moment, boxes are implemented as structures, but that may
change. In particular, you should not depend on being able to
recognize boxes using a type or predicate."
  value)

(setf (documentation 'box 'function)
      "Box a value.")

(defmethod print-object ((self box) stream)
  (print-unreadable-object (self stream :type t :identity t)
    (format stream "~a" (unbox self))))

(defmethod make-load-form ((self box) &optional env)
  (declare (ignore env))
  (values `(box)
          `(setf (unbox ',self) ,(unbox self))))

(declaim (inline unbox (setf unbox)))

(defun unbox (x)
  "The value in the box X."
  (box-value x))

(defun (setf unbox) (value x)
  "Put VALUE in box X."
  (setf (box-value x) value))
