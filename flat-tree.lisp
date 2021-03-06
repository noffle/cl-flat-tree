;;               7 
;;       3                11
;;   1       5       9          13
;; 0   2   4   6   8   10   12     14

(in-package :flat-tree)

(defmacro multf (place amt)
  "Like 'incf', but for multiplication."
  `(setf ,place (* ,place ,amt)))

(defun index (depth offset)
  "Returns an array index for the tree element at the given depth and offset."
  (+
   (1- (expt 2 depth))
   (* (expt 2 (1+ depth)) offset)))

(defun depth-n? (index depth)
  "Returns T if 'index' is of depth 'depth'."
  (= 0 (mod (- index (1- (expt 2 depth))) (expt 2 (1+ depth)))))

(defun depth (index)
  "Returns the depth of an index."
  (let ((depth 0))
    (loop
       until (depth-n? index depth)
       do (incf depth))
    depth))

(defun step-size (depth)
  "Returns the offset step size, given 'depth'."
  (expt 2 (1+ depth)))

(defun offset (index)
  "Returns the offset of an index."
  (let* ((d (depth index))
         (step (step-size d)))
    (decf index (1- (expt 2 d)))
    (/ index step)))

(defun sibling (index)
  "Returns the index of this element's sibling."
  (if (evenp (offset index))
      (+ index (step-size (depth index)))
      (- index (step-size (depth index)))))

(defun parent (index)
  "Returns the index of the parent element in tree."
  (/ (+ index (sibling index)) 2))

(defun children (index)
  "Returns a list (leftChild rightChild) with the indexes of this element's children.
If this element does not have any children it returns NIL."
  (let* ((d (depth index))
         (step (/ (step-size (1- d)) 2)))
    (if (= d 0) nil
        (list (- index step) (+ index step)))))

(defun left-span (index)
  "Returns the left spanning in index in the tree index spans."
  (let ((step (1- (expt 2 (depth index)))))
    (- index step)))

(defun right-span (index)
  "Returns the right spanning in index in the tree index spans."
  (let ((step (1- (expt 2 (depth index)))))
    (+ index step)))

(defun spans (index)
  "Returns the range (inclusive) that the tree rooted at 'index' spans.
For example (spans 3) would return (0 6)."
  (list (left-span index) (right-span index)))

(defun counts (index)
  "Returns how many nodes (including parent nodes) a tree contains."
  (1- (expt 2 (1+ (depth index)))))

(defun full-roots (index)
  "Returns a list of all the full roots (subtrees where all nodes have either 2 or 0 children) < index.

For example (full-roots 8) returns (3), since the subtree rooted at 3 spans 0 -> 6 and the tree rooted at 7 has a child located at 9 which is >= 8."
  (when (not (evenp index)) (error "You can only look roots for depth=0 nodes"))
  (setf index (/ index 2))
  (let ((result nil)
        (offset 0)
        (factor 1))
    (loop until (= index 0)
       do (progn
            (loop while (<= (* factor 2) index) do (setf factor (* factor 2)))
            (push (+ offset factor -1) result)
            (incf offset (* 2 factor))
            (decf index factor)
            (setf factor 1)))
    (nreverse result)))

(defstruct iterator
  (index 0)
  (step-size 2)
  (offset 0)
  (depth 0))

(defun iterator-next (iter)
  "Move one step right across the tree, at the current depth."
  (incf (iterator-index iter) (iterator-step-size iter))
  (incf (iterator-offset iter)))

(defun iterator-prev (iter)
  "Move one step left across the tree, at the current depth."
  (when (> (iterator-offset iter) 0)
    (decf (iterator-index iter) (iterator-step-size iter))
    (decf (iterator-offset iter))))
  
(defun iterator-seek (iter index)
  "Move the iterator to a specific index."
  (let* ((d (depth index))
         (step (step-size d)))
    (setf (iterator-index iter) index)
    (setf (iterator-step-size iter) step)
    (setf (iterator-offset iter) (/ (- index (1- (expt 2 d))) step))
    (setf (iterator-depth iter) d)))

(defun iterator-parent (iter)
  "Move the iterator to its parent."
  (incf (iterator-depth iter))
  (setf (iterator-index iter) (/ (+ (iterator-index iter)
                                    (if (evenp (iterator-offset iter))
                                        (+ (iterator-index iter)
                                           (iterator-step-size iter))
                                        (- (iterator-index iter)
                                           (iterator-step-size iter))))
                                 2))
  (setf (iterator-offset iter) (floor (/ (iterator-offset iter) 2)))
  (setf (iterator-step-size iter) (* 2 (iterator-step-size iter))))

(defun iterator-left-child (iter)
  "Move the iterator to its left child. No change if there is no child."
  (when (> (iterator-depth iter) 0)
    (decf (iterator-depth iter))
    (decf (iterator-index iter) (/ (step-size (iterator-depth iter)) 2))
    (multf (iterator-offset iter) 2)
    (setf (iterator-step-size iter) (step-size (iterator-depth iter)))))

(defun iterator-right-child (iter)
  "Move the iterator to its right child. No change if there is no child."
  (when (> (iterator-depth iter) 0)
    (decf (iterator-depth iter))
    (incf (iterator-index iter) (/ (step-size (iterator-depth iter)) 2))
    (setf (iterator-offset iter) (1+ (* (iterator-offset iter) 2)))
    (setf (iterator-step-size iter) (step-size (iterator-depth iter)))))

(defun iterator-left-span (iter)
  "Move the iterator to the current left span index."
  (multf (iterator-offset iter) (expt 2 (iterator-depth iter)))
  (decf (iterator-index iter)
        (1- (expt 2 (iterator-depth iter))))
  (setf (iterator-depth iter) 0)
  (setf (iterator-step-size iter) 2))

(defun iterator-right-span (iter)
  "Move the iterator to the current right span index."
  (dotimes (n (iterator-depth iter))
    (setf (iterator-offset iter) (1+ (* (iterator-offset iter) 2))))
  (incf (iterator-index iter)
        (1- (expt 2 (iterator-depth iter))))
  (setf (iterator-depth iter) 0)
  (setf (iterator-step-size iter) 2))

(defun iterator-is-left? (iter)
  "Is the iterator at a left sibling?"
  (evenp (iterator-offset iter)))

(defun iterator-is-right? (iter)
  "Is the iterator at a right sibling?"
  (not (iterator-is-left? iter)))

(defun iterator-sibling (iter)
  "Move the iterator to its sibling."
  (if (iterator-is-left? iter)
      (progn
        (incf (iterator-offset iter))
        (incf (iterator-index iter) (step-size (iterator-depth iter))))
      (progn
        (decf (iterator-offset iter))
        (decf (iterator-index iter) (step-size (iterator-depth iter))))))
