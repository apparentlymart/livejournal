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

function Poll(selectPoll, qDoc, sDoc, qNum){
	if(typeof selectPoll == 'string'){
		// IE custom tags. http://msdn.microsoft.com/en-us/library/ms531076%28VS.85%29.aspx
		selectPoll = jQuery(selectPoll.replace(/<(\/?)lj-(poll|pq|pi)(>| )/gi, '<$1lj:$2$3'));
		var tagPrefix = jQuery.browser.msie && Number(jQuery.browser.version) < 9 ? '' : 'lj\\:';

		this.name = selectPoll.attr('name');
		this.whovote = selectPoll.attr('whovote');
		this.whoview = selectPoll.attr('whoview');
		this.questions = [];

		selectPoll.find(tagPrefix + 'pq').each(function(i, pq){
			var question = {
				name: pq.firstChild.nodeValue || '',
				type: pq.getAttribute('type'),
				answers: []
			};

			if(!/^check|drop|radio|scale|text$/.test(question.type)){
				return;
			}
			pq = jQuery(pq);
			if(/^check|drop|radio$/.test(question.type)){
				pq.find(tagPrefix + 'pi').each(function(){
					question.answers.push(jQuery(this).html())
				});
			}
			if(question.type == 'text'){
				question.size = pq.attr('size');
				question.maxlength = pq.attr('maxlength');
			}
			if(question.type == 'scale'){
				question.from = pq.attr('from');
				question.to = pq.attr('to');
				question.by = pq.attr('by');
			}
			this.questions.push(question);
		}.bind(this));
	} else if(selectPoll != void 0) {
		this.name = sDoc.poll.name.value || '';
		this.whovote = jQuery(sDoc.poll.whovote).filter(':checked').val();
		this.whoview = jQuery(sDoc.poll.whoview).filter(':checked').val();
		// Array of Questions and Answers
		// A single poll can have multiple questions
		// Each question can have one or several answers
		this.questions = [];
		for(var i = 0; i < qNum; i++){
			this.questions[i] = new Answer(qDoc, i);
		}
	} else {
		this.name = '';
		this.whoview = this.whovote = 'all';
		this.questions = [];
	}
}

// Poll method to generate HTML for RTE
Poll.prototype.outputHTML = function(){
	var html = '<form action="#" class="rte-poll-form"><h1>Poll #xxxx';

	if(this.name){
		html += ' <i>' + this.name + '</i>';
	}
	html += '</h1><p>Open to: ' + '<b>' + this.whovote + '</b>, results viewable to: ' + '<b>' + this.whoview + '</b></p><div class="rte-poll">';
	for(var i = 0; i < this.questions.length; i++){
		html += '<h2>' + this.questions[i].name + '</h2>';
		if(this.questions[i].type == 'radio' || this.questions[i].type == 'check'){
			var type = this.questions[i].type == 'check' ? 'checkbox' : this.questions[i].type;
			html += '<ul>';
			for(var j = 0; j < this.questions[i].answers.length; j++){
				html += '<li><input type="' + type + '">' + this.questions[i].answers[j] + '</li>';
			}
			html += '</ul>';
		} else if(this.questions[i].type == 'drop'){
			html += '<p><select name="select_' + i + '">' + '<option value=""></option>';
			for(var j = 0; j < this.questions[i].answers.length; j++){
				html += '<option value="">' + this.questions[i].answers[j] + '</option>';
			}
			html += '</select></p>';
		} else if(this.questions[i].type == 'text'){
			html += '<p><input maxlength="' + this.questions[i].maxlength + '" size="' + this.questions[i]
				.size + '" type="text"/></p>';
		} else if(this.questions[i].type == 'scale'){
			html += '<table><tbody><tr align="center" valign="top">';
			var from = Number(this.questions[i].from),
				to = Number(this.questions[i].to),
				by = Number(this.questions[i].by);
			for(var j = from; j <= to; j = j + by){
				html += '<td><input type="radio" id=' + RTEPollScaleRadio + 'j/><br /><label for=RTEPollScaleRadio' + j + '>' + j + '</label></td>';
			}
			html += '</tr></tbody></table>';
		}
	}

	html += '</div><p><input type="submit" value="Submit Poll"/></p></form>';
	return encodeURIComponent(html);
};

// Poll method to generate LJ Poll tags
Poll.prototype.outputLJtags = function(){
	var tags = '';

	tags += '<lj-poll name="' + this.name + '" whovote="' + this.whovote + '" whoview="' + this.whoview + '"><br />';

	for(var i = 0; i < this.questions.length; i++){
		var extrargs = '';
		if(this.questions[i].type == 'text'){
			extrargs = ' size="' + this.questions[i].size + '"' + ' maxlength="' + this.questions[i].maxlength + '"';
		} else if(this.questions[i].type == 'scale'){
			extrargs = ' from="' + this.questions[i].from + '"' + ' to="' + this.questions[i].to + '"' + ' by="' + this
				.questions[i].by + '"';
		}
		tags += '<lj-pq type="' + this.questions[i].type + '"' + extrargs + '>' + this.questions[i].name + '<br />';
		if(/^check|drop|radio$/.test(this.questions[i].type)){
			for(var j = 0; j < this.questions[i].answers.length; j++){
				tags += '<lj-pi>' + this.questions[i].answers[j] + '</lj-pi><br />';
			}
		}
		tags += '</lj-pq><br />';
	}

	tags += '</lj-poll>';

	return encodeURIComponent(tags);
};

// Answer Object Constructor
function Answer(doc, id){
	var form = doc.poll;
	this.name = form['question_' + id].value;
	this.type = jQuery(form['type_' + id]).val();

	this.answers = [];
	if(/^check|drop|radio$/.test(this.type)){

		jQuery('#QandA_' + id + ' input[name^="answer_' + id + '_"][value!=""]', form).each(function(i, node){
			this.answers.push(node.value);
		}.bind(this));
	} else if(this.type == 'text'){
		this.size = form['pq_' + id + '_size'].value;
		this.maxlength = form['pq_' + id + '_maxlength'].value;
	} else if(this.type == 'scale'){
		this.from = form['pq_' + id + '_from'].value;
		this.to = form['pq_' + id + '_to'].value;
		this.by = form['pq_' + id + '_by'].value;
	}
}
