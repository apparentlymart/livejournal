/* Poll structure:
 name: string
 whovote: all | friends
 whoview: all | friends | none
 questions: {[
 name: string
 type: check | drop | radio | scale | text
 size: string      // if type is text
 maxlength: string // if type is text
 from: string // if type is scale
 to: string   // if type is scale
 by: string   // if type is scale
 answers: [string, ...] // if type is check | drop | radio
 ], ...}
 */

var Poll = (function(){
	// Answer Object Constructor
	function Answer(doc, id) {
		var form = doc.poll,
			answer = this;

		this.name = form['question_' + id].value;
		this.type = jQuery(form['type_' + id]).val();
		this.answers = [];

		switch (this.type) {
			case 'check':
			case 'drop':
			case 'radio':
				jQuery('#QandA_' + id + ' input[name^="answer_' + id + '_"][value!=""]', form).each(function(i, node) {
					answer.answers.push(node.value);
				});
				break;
			case 'text':
				this.size = form['pq_' + id + '_size'].value;
				this.maxlength = form['pq_' + id + '_maxlength'].value;
				break;
			case 'scale':
				this.from = form['pq_' + id + '_from'].value;
				this.to = form['pq_' + id + '_to'].value;
				this.by = form['pq_' + id + '_by'].value;
				break;
		}
	}

	function Constructor(selectPoll, qDoc, sDoc, qNum) {
		if (typeof selectPoll == 'string') {
			// IE custom tags. http://msdn.microsoft.com/en-us/library/ms531076%28VS.85%29.aspx
			selectPoll = jQuery(selectPoll.replace(/<(\/?)lj-(poll|pq|pi)(>| )/gi, '<$1lj:$2$3'));
			var tagPrefix = jQuery.browser.msie && Number(jQuery.browser.version) < 9 ? '' : 'lj\\:',
				poll = this;

			this.name = selectPoll.attr('name');
			this.whovote = selectPoll.attr('whovote');
			this.whoview = selectPoll.attr('whoview');
			this.questions = [];

			selectPoll.find(tagPrefix + 'pq').each(function(i, pq) {
				var question = {
					name: pq.firstChild.nodeValue || '',
					type: pq.getAttribute('type'),
					answers: []
				};

				if (!/^check|drop|radio|scale|text$/.test(question.type)) {
					return;
				}

				pq = jQuery(pq);

				switch (question.type) {
					case 'check':
					case 'drop':
					case 'radio':
						pq.find(tagPrefix + 'pi').each(function() {
							question.answers.push(jQuery(this).html());
						});
						break;
					case 'text':
						question.size = pq.attr('size');
						question.maxlength = pq.attr('maxlength');
						break;
					case 'scale':
						question.from = pq.attr('from');
						question.to = pq.attr('to');
						question.by = pq.attr('by');
						break;
				}

				poll.questions.push(question);
			});

		} else if (selectPoll != void 0) {
			this.name = sDoc.poll.name.value || '';
			this.whovote = jQuery(sDoc.poll.whovote).filter(':checked').val();
			this.whoview = jQuery(sDoc.poll.whoview).filter(':checked').val();
			this.questions = [];
			for (var i = 0; i < qNum; i++) {
				this.questions[i] = new Answer(qDoc, i);
			}
		} else {
			this.name = '';
			this.whoview = this.whovote = 'all';
			this.questions = [];
		}
	}

	// Poll method to generate HTML for RTE
	Constructor.prototype.outputHTML = function() {
		var html = '<form action="#" class="rte-poll-form"><div class="rte-poll-head"><h1>Poll #xxxx';

		if (this.name) {
			html += ' <i>' + this.name + '</i>';
		}

		html += '</h1><p>Open to: ' + '<b>' + this.whovote + '</b>, results viewable to: ' + '<b>' + this.whoview + '</b></p></div><div class="rte-poll">';

		for (var i = 0; i < this.questions.length; i++) {
			var question = this.questions[i],
				j;

			html += '<h2>' + question.name + '</h2>';

			switch (question.type) {
				case 'drop':
					html += '<p><select name="select_' + i + '">' + '<option value=""></option>';

					for (j = 0; j < question.answers.length; j++) {
						html += '<option value="">' + question.answers[j] + '</option>';
					}

					html += '</select></p>';
					break;
				case 'text':
					html += '<p><input maxlength="' + question.maxlength + '" size="' + question.size + '" type="text"/></p>';
					break;
				case 'scale':
					var from = Number(question.from),
						to = Number(question.to),
						by = Number(question.by);

					html += '<table><tbody><tr align="center" valign="top">';

					for (j = from; j <= to; j = j + by) {
						html += '<td><input type="radio" id=' + RTEPollScaleRadio + 'j/><br /><label for=RTEPollScaleRadio' + j + '>' + j + '</label></td>';
					}

					html += '</tr></tbody></table>';
					break;
				case 'radio':
				case 'check':
					var type = question.type == 'check' ? 'checkbox' : question.type;

					html += '<ul>';

					for (j = 0; j < question.answers.length; j++) {
						html += '<li><input type="' + type + '">' + question.answers[j] + '</li>';
					}

					html += '</ul>';
					break;
			}
		}

		html += '<p><input type="submit" value="Submit Poll"/></p></div></form>';
		return encodeURIComponent(html);
	};

	// Poll method to generate LJ Poll tags
	Constructor.prototype.outputLJtags = function() {
		var html = '<lj-poll name="' + this.name + '" whovote="' + this.whovote + '" whoview="' + this.whoview + '"><br />';

		for (var i = 0; i < this.questions.length; i++) {
			var extrargs = '',
				question = this.questions[i];

			if (question.type == 'text') {
				extrargs = ' size="' + question.size + '"' + ' maxlength="' + question.maxlength + '"';
			} else if (question.type == 'scale') {
				extrargs = ' from="' + question.from + '"' + ' to="' + question.to + '"' + ' by="' + question.by + '"';
			}

			html += '<lj-pq type="' + question.type + '"' + extrargs + '>' + question.name + '<br />';

			if (/^check|drop|radio$/.test(question.type)) {
				for (var j = 0; j < question.answers.length; j++) {
					html += '<lj-pi>' + question.answers[j] + '</lj-pi><br />';
				}
			}

			html += '</lj-pq><br />';
		}

		html += '</lj-poll>';

		return encodeURIComponent(html);
	};

	return Constructor;
})();