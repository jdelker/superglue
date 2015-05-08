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

var log_prefix = '[reg-push-janet] ';

function fail(msg) {
    throw new Error(log_prefix + msg);
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
'usage: casperjs reg-push-janet.js --creds=<file> --domain=<domain> <ns>...\n
	--creds=<file>		Path to credentials file
	--domain=<domain>	The domain to update
	<ns>...			The list of name server names

The credentials file may contain blank lines or lines starting with a "#"
to mark comments. The other lines have the form "<keyword><space><value>".
There must be lines containing the keywords "user" and "pass".
');
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
    this.fillSelectors('form#form1', {
	'#MainContent_Login1_UserName': creds.user,
	'#MainContent_Login1_Password': creds.pass,
    });
    this.click('#MainContent_Login1_LoginButton');
});

casper.then(function greeting() {
    info("Loaded greeting page: " + this.getTitle());
    this.click('#commonActionsMenu_ListDomains');
});

casper.then(function choose_domain() {
    info("Loaded domain list: " + this.getTitle());
    this.fillSelectors('form#form1', {
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
	    return td.innerHTML;
	}, sel);
	info('Found domain: ' + res);
	if (res === domain) {
	    this.click(sel);
	    break;
	}
    }
});

casper.then(function open_domain() {
    info("Loaded domain details: " + this.getTitle());
    var tbl = this.getElementsInfo('#MainContent_nameServersTab td');
    if (tbl.length % 4 !== 0 || tbl[1].text !== 'Name')
	fail('Could not parse name server list for ' + domain);
    var ns = [];
    for (var j = 0, i = 5; i < tbl.length; i += 4, j += 1)
	ns[j] = tbl[i].text;
    ns.sort();
    for (var i = 0; i < ns.length; i++)
	info(domain + ' NS ' + ns[i]);
});

casper.then(function () {
    info("Loaded page: " + this.getTitle());
    this.echo(this.page.plainText);
});

casper.run();
