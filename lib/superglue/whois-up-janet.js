/*
 * Drive the https://domainregistry.jisc.ac.uk/dns/ web site for whois updates
 */

"use strict";

var casper = require('casper').create({
    verbose: true,
    exitOnError: true,
});

var fs = require('fs');
var system = require('system');
var utils = require('utils');

var log_prefix = 'whois-up-janet: ';

function quit(x) {
    casper.exit(x);
    casper.bypass(999);
}

function fail(msg) {
    casper.die(log_prefix + msg);
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
'usage: casperjs [--log-level=<level>] whois-up-janet.js\n'+
'                [--ignore-tickets] [--ignore-match] [--not-really]\n'+
'                 --creds=<file> <domain>\n'+
'	--log-leve=<level>	Set "info" or "debug" mode\n'+
'	--ignore-tickets	Update even if the domain has pending tickets\n'+
'	--ignore-match		Update even if its delegation matches\n'+
'	--not-really		Stop at the last moment\n'+
'	--creds=<file>		Path to credentials file\n'+
'	<domain>		The domain to update\n'+
'	stdin			whois contact details in JSON\n'
);
    quit(1);
}

var re_dname = /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?[.])+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/;

if (casper.cli.args.length !== 1) usage();
var domain = casper.cli.args[0].toLowerCase();
if (!domain.match(re_dname)) usage();

var registrant = (function load_registrant() {
    var r = JSON.parse(system.stdin.read());
    for (var k in r) {
	debug(k + ": " + r[k]);
    }
    return r;
})();

var creds = (function load_creds() {
    var c = {};
    var file = casper.cli.options.creds;
    if (!file) usage();
    var stream = fs.open(file, 'r');
    for (var n = 1; !stream.atEnd(); n++) {
	var line = stream.readLine();
	if (line.match(/^\s*#|^\s*$/))
	    continue;
	var match = line.match(/^(\S+)\s+(.*)$/)
	if (!match)
	    fail('read '+file+':'+n+': could not parse line: '+line);
	c[match[1]] = match[2];
	if (match[1] === 'pass')
	    debug('pass ********');
	else
	    debug(match[1]+" "+match[2]);
    }
    return c;
})();

casper.start('https://domainregistry.jisc.ac.uk/dns', function started() {
    debug(this.fetchText('h1'));
});

casper.then(function login() {
    info("Loaded login page: " + this.fetchText('h1'));
    this.fillSelectors('form', {
	'#MainContent_Login1_UserName': creds.user,
	'#MainContent_Login1_Password': creds.pass,
    });
    this.click('#MainContent_Login1_LoginButton');
});

casper.then(function greeting() {
    var title = this.getTitle();
    info("Loaded greeting page: "+title);
    if (title !== 'Domain Registry Service')
	fail('Login failed');
    this.click('#commonActionsMenuLogin_ListPendingTickets');
});

casper.then(function view_tickets() {
    info("Loaded tickets: " + this.fetchText('h1'));
    this.fillSelectors('form', {
	'#MainContent_TicketTypeChoice': 'Modification'
    });
    this.click('#MainContent_FilterSubmit');
});

casper.then(function count_tickets() {
    info("Loaded modification tickets: " + this.fetchText('h1'));
    var table = this.getElementsInfo('#MainContent_TicketListView tr');
    var n = table.length - 2;
    info("Pending modifications: "+n);
    if (n >= 10) {
	notice("Too many pending modifications");
	quit(1);
    }
    this.fillSelectors('form', {
	'#MainContent_TicketTypeChoice': '',
	'#MainContent_DomainFilterInput': domain
    });
    this.click('#MainContent_FilterSubmit');
});

casper.then(function find_tickets() {
    info("Loaded filtered tickets: " + this.fetchText('h1'));
    var clicky = true;
    if (this.exists('#MainContent_TicketListView_CurrentPageLabel')) {
	notice('Changes pending for ' + domain);
	if (casper.cli.options['ignore-tickets'])
	    notice('Ignoring tickets');
	else
	    clicky = false
    }
    if (clicky)
	this.click('#commonActionsMenuLogin_ListDomains');
    else
	quit(0);
});

casper.then(function choose_domain() {
    info("Loaded domain list: " + this.fetchText('h1'));
    this.fillSelectors('form', {
	'#MainContent_tbDomainNames': domain,
	'#MainContent_ShowReverseDelegatedDomains': true,
    });
    this.click('#MainContent_btnFilter');
});

casper.then(function find_domain() {
    info("Loaded filtered list: " + this.fetchText('h1'));
    for (var i = 0; ; i++) {
	var table_id = '#MainContent_DomainListView';
	var button_id = table_id+'_ViewDomainNumber'+i+'_'+i;
	var domain_sel = table_id+' > tbody '+
	    '> tr:nth-child('+(i+1)+') '+
	    '> td:nth-child(4)';
	var found = this.fetchText(domain_sel);
	if (!found)
	    fail('Could not find domain number '+i+' searching for '+domain);
	info('Found domain number '+i+' '+found);
	if (found === domain) {
	    this.click(button_id);
	    break;
	}
    }
});

casper.then(function open_domain() {
    info("Loaded domain details: " + this.fetchText('h1'));
    var id = '#MainContent_Reg';
    var match = true;
    for (var k in registrant) {
	var t = this.fetchText(id+k);
	var arrow = ' == ';
	if (t !== registrant[k]) {
	    match = false;
	    arrow = ' -> ';
	}
	info('checking '+k+' '+t+arrow+registrant[k]);
    }
    if (match) {
	info('No need to modify delegation of ' + domain)
	quit(0);
    } else {
	info('Modifying registrant of ' + domain)
	this.click('#MainContent_ModifyDomainButton');
    }
});

var modwhen_id = '#MainContent_ModificationDate_Modification';

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
    form[modwhen_id+'Time'] = tv;
    form[modwhen_id+'DateCalendar'] = d;
    notice('Modification scheduled at '+t+' '+d+' '+dd+' for '+domain);
}

casper.then(function fill_form() {
    info("Loaded modification form: " + this.fetchText('h1'));
    var id = '#MainContent_Registrant_Reg';
    var form = {};
    for (var k in registrant) {
	if (k === 'PostCode')
	    form[id+'Postcode'] = registrant[k];
	else
	    form[id+k] = registrant[k];
    }
    var now = HH_MM(new Date(Date.now() + 5 * 60 * 1000));
    var today = false;
    var times = this.getElementsInfo(modwhen_id+'Time option');
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
    if (casper.cli.options['not-really']) {
	notice('Not really!');
	quit(0);
    } else {
	this.click('#MainContent_ConfirmRequest');
    }
});

casper.waitForUrl(/ViewPendingTickets/,
function change_submitted() {
    if (this.exists('#MainContent_SubmissionText')) {
	notice(this.getElementInfo('#MainContent_SubmissionText').text);
	quit(0);
    } else {
	this.echo(this.page.plainText);
	fail('Unexpected response after submbitting modification for ' + domain);
    }
},
function onTimeout() {
    fail('Timeout after submitting modification for ' + domain);
});

casper.run();
