/*
 * Drive the naming.ja.net/dns web site
 */

"use strict";

// TODO: get these from the command line

var creds_file = '/home/ipreg/DNS/conf/creds/janet';
var log_prefix = '[reg-push-janet] ';

var domain = 'cudos.ac.uk';

var casper = require('casper').create({
    verbose: true,
});

var fs = require('fs');
var utils = require('utils');

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

casper.then(function open_domain() {
    info("Loaded domain list: " + this.getTitle());
    for (var i = 0; ; i++) {
	var sel = '#MainContent_DomainListView_ViewDomainNumber'+i+'_'+i;
	if (!this.exists(sel))
	    fail('Could not find domain: '+domain);

    });
    this.click('#MainContent_btnFilter');
});

casper.then(function () {
    info("Loaded page: " + this.getTitle());
    this.echo(this.page.plainText);
});

casper.run();
