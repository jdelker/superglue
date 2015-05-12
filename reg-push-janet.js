/*
 * Drive the https://naming.ja.net/dns/ web site
 *
 * This site relies a lot on Javascript, which is why we are using
 * PhantomJS and CasperJS rather than trying to treat the web server
 * like a REST-ish API endpoint.
 *
 * We are mostly relying on element IDs for navigating the site. But the whole
 * thing smells of being generated with a complicated framework, so there is
 * little chance that these IDs will remain stable if the site is revised.
 *
 * Sadly I suspect this script will be rather fragile.
 */

"use strict";

var casper = require('casper').create({
    verbose: true,
});

var fs = require('fs');
var utils = require('utils');

var log_prefix = 'reg-push-janet: ';

function fail(msg) {
    throw new Error(log_prefix + msg);
}
function notice(msg) {
    casper.echo(log_prefix + msg);
}
function logfn(pri) {
    return function log(msg) {
	casper.log(log_prefix + msg, pri);
    }
}
var error = logfn('error');
var info  = logfn('info');
var debug = logfn('debug');

function usage() {
    console.log(
'usage: casperjs reg-push-janet.js --creds=<file> --domain=<domain> <ns>...\n'+
'	--creds=<file>		Path to credentials file\n'+
'	--domain=<domain>	The domain to update\n'+
'	<ns>...			The list of name server names\n'+
'\n'+
'The credentials file may contain blank lines or lines starting with a "#"\n'+
'to mark comments. The other lines have the form "<keyword><space><value>".\n'+
'There must be lines containing the keywords "user" and "pass".\n');
    phantom.exit(1);
}

var creds_file = casper.cli.options.creds;
if (!creds_file) usage();

var domain = casper.cli.options.domain;
if (!domain) usage();

var set_ns = casper.cli.args;
if (!set_ns.length) usage();
set_ns = set_ns.slice(0).sort();

var creds = (function load_creds() {
    var c = {};
    var stream = fs.open(creds_file, 'r');
    while(!stream.atEnd()) {
	var line = stream.readLine();
	if (line.match(/^\s*#|^\s*$/))
	    continue;
	var match = line.match(/^(\S+)\s+(.*)$/)
	if (!match)
	    fail('read '+creds_file+': could not parse line: '+line);
	c[match[1]] = match[2];
	if (match[1] === 'pass')
	    debug('pass ********');
	else
	    debug(match[1]+" "+match[2]);
    }
    return c;
})();

casper.start('https://naming.ja.net/dns');

casper.then(function login() {
    info("Loaded login page: " + this.getTitle());
    this.fillSelectors('form', {
	'#MainContent_Login1_UserName': creds.user,
	'#MainContent_Login1_Password': creds.pass,
    });
    this.click('#MainContent_Login1_LoginButton');
});

casper.then(function greeting() {
    info("Loaded greeting page: " + this.getTitle());
    this.click('#commonActionsMenu_ListPendingTickets');
});

casper.then(function view_tickets() {
    info("Loaded tickets: " + this.getTitle());
    this.fillSelectors('form', {
	'#MainContent_DomainFilterInput': domain
    });
    this.click('#MainContent_FilterSubmit');
});

casper.then(function find_tickets() {
    info("Loaded filtered tickets: " + this.getTitle());
    if (this.exists('#MainContent_TicketListView_CurrentPageLabel')) {
	info('Changes pending for ' + domain);
	this.exit(0);
    } else {
	this.click('#commonActionsMenu_ListDomains');
    }
});

casper.then(function choose_domain() {
    info("Loaded domain list: " + this.getTitle());
    this.fillSelectors('form', {
	'#MainContent_tbDomainNames': domain
    });
    this.click('#MainContent_btnFilter');
});

casper.then(function find_domain() {
    info("Loaded filtered list: " + this.getTitle());
    for (var i = 0; ; i++) {
	var sel = '#MainContent_DomainListView_ViewDomainNumber'+i+'_'+i;
	if (!this.exists(sel))
	    fail('Could not find domain: ' + domain);
	// Unfortunately there isn't a sensible selector for each row of the
	// search results table, so we have to dig around for the cousin node
	// which might contain the name of the domain we are looking for.
	var res = this.evaluate(function find_domain(sel) {
	    var a = document.querySelector(sel);
	    var tr = a.parentNode.parentNode;
	    var td = tr.childNodes[3];
	    return td.innerHTML.toLowerCase();
	}, sel);
	info('Found domain: ' + res);
	if (res === domain) {
	    this.click(sel);
	    break;
	}
    }
});

var got_ns = [];

casper.then(function open_domain() {
    info("Loaded domain details: " + this.getTitle());
    var tbl = this.getElementsInfo('#MainContent_nameServersTab td');
    if (tbl.length % 4 !== 0 || tbl[1].text !== 'Name')
	fail('Could not parse name server list for ' + domain);
    for (var j = 0, i = 5; i < tbl.length; i += 4, j += 1)
	got_ns[j] = tbl[i].text;
    got_ns.sort();
    var match = true;
    for (var i = 0; i < got_ns.length; i++) {
	if (got_ns[i] !== set_ns[i])
	    match = false;
    }
    if (match && got_ns.length === set_ns.length) {
	info('No need to modify delegation of ' + domain)
	this.exit(0);
    } else {
	info('Modifying delegation of ' + domain)
	this.click('#MainContent_ModifyDomainButton');
    }
});

var nsec_id = '#MainContent_NumberOfSecServers';
function get_nsec() {
    return casper.getElementInfo(nsec_id + ' option[selected]').text;
}
function report_nsec() {
    var nsec = get_nsec();
    info('Number of secondaries for ' + domain + ' is ' + nsec);
    return nsec;
}

casper.then(function set_number_of_secondaries() {
    info("Loaded page: " + this.getTitle());
    var nsec = report_nsec();
    var form = {};
    form[nsec_id] = set_ns.length - 1;
    if (form[nsec_id] !== nsec)
	this.fillSelectors('form', form);
});

function twoDigit(n) {
    if (n < 10) return '0' + n;
    else return '' + n;
}
function HH_MM(d) {
    return twoDigit(d.getHours())+':'+twoDigit(d.getMinutes());
}
function dd_mm_yyyy(d) {
    return twoDigit(d.getDate()) + '/' +
	   twoDigit(d.getMonth()+1) + '/' + d.getFullYear();
}
function set_form_time(form, time, today) {
    var t = time.text;
    var tv = time.attributes.value;
    var d = dd_mm_yyyy(new Date(Date.now() +
				(today ? 0 : 24 * 60 * 60 * 1000)));
    var dd = today ? 'today' : 'tomorrow';
    form['#MainContent_ModificationTime'] = tv;
    form['#MainContent_ModificationDateCalendar'] = d;
    notice('Modification scheduled at '+t+' '+d+' '+dd+' for '+domain);
    notice('Old NS RRset');
    for (var i = 0; i < got_ns.length; i++)
	notice(domain + ' NS ' + got_ns[i]);
    notice('New NS RRset');
    for (var i = 0; i < set_ns.length; i++)
	notice(domain + ' NS ' + set_ns[i]);
}

casper.waitForSelector('#MainContent_SecAddress'+(set_ns.length-2),
function set_nameservers() {
    var n = set_ns.length;
    if (report_nsec() !== ''+(n-1))
	fail('Unable to resize nameserver form for ' + domain);
    var form = {}
    form['#MainContent_PrimeNameserverName'] = set_ns[n-1];
    for (var i = 0; i < n-1; i++)
	form['#MainContent_SecAddress'+i] = set_ns[i];
    var now = HH_MM(new Date(Date.now() + 5 * 60 * 1000));
    var today = false;
    var times = this.getElementsInfo('#MainContent_ModificationTime option');
    for (var i = 0; i < times.length; i++) {
	if (now < times[i].text) {
	    set_form_time(form, times[i], today = true);
	    break;
	}
    }
    if (!today) {
	set_form_time(form, times[0], today = false);
    }
    this.fillSelectors('form', form);
    this.click('#MainContent_ConfirmRequest');
},
function onTimeout() {
    fail('Timeout while filling modification form for ' + domain);
});

casper.waitForUrl(/ViewPendingTickets/,
function change_submitted() {
    if (this.exists('#MainContent_SubmissionText')) {
	notice(this.getElementInfo('#MainContent_SubmissionText').text);
	this.exit(0);
    } else {
	this.echo(this.page.plainText);
	fail('Unexpected response after submbitting modification for ' + domain);
    }
},
function onTimeout() {
    fail('Timeout after submitting modification for ' + domain);
});

casper.run();
