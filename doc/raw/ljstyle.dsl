<!DOCTYPE style-sheet PUBLIC "-//James Clark//DTD DSSSL Style Sheet//EN" [
<!ENTITY html-ss
	 SYSTEM
	 "/usr/lib/sgml/stylesheet/dsssl/docbook/nwalsh/html/docbook.dsl" CDATA dsssl>
]>

<style-sheet>
<style-specification id="html" use="html-stylesheet">
<style-specification-body>

(element emphasis
  (if (equal? (normalize "bold") (attribute-string (normalize "role")))
      ($bold-seq$)
      ($italic-seq$)))

</style-specification-body>
</style-specification>

<external-specification id="html-stylesheet" document="html-ss">
</style-sheet>
