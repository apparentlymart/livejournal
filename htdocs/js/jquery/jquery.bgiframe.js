/*! Copyright (c) 2010 Brandon Aaron (http://brandonaaron.net)
* Licensed under the MIT License (LICENSE.txt).
*
* Version 2.1.3-pre
*/
(function(a){a.fn.bgiframe=a.browser.msie&&/msie 6\.0/i.test(navigator.userAgent)?function(d){var c="auto";d=a.extend({top:c,left:c,width:c,height:c,opacity:true,src:"javascript:false;"},d);var e='<iframe class="bgiframe"frameborder="0"tabindex="-1"src="'+d.src+'"style="display:block;position:absolute;z-index:-1;'+(d.opacity!==false?"filter:Alpha(Opacity='0');":"")+"top:"+(d.top==c?"expression(((parseInt(this.parentNode.currentStyle.borderTopWidth)||0)*-1)+'px')":b(d.top))+";left:"+(d.left==c?"expression(((parseInt(this.parentNode.currentStyle.borderLeftWidth)||0)*-1)+'px')":b(d.left))+";width:"+(d.width==c?"expression(this.parentNode.offsetWidth+'px')":b(d.width))+";height:"+(d.height==c?"expression(this.parentNode.offsetHeight+'px')":b(d.height))+';"/>';return this.each(function(){a(this).children("iframe.bgiframe").length===0&&this.insertBefore(document.createElement(e),this.firstChild)})}:function(){return this};a.fn.bgIframe=a.fn.bgiframe;function b(a){return a&&a.constructor===Number?a+"px":a}})(jQuery);

