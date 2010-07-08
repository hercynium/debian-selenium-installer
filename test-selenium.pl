#!/usr/bin/env perl
use strict;
use warnings;
use Test::WWW::Selenium;
use Test::More "no_plan";

my $sel = Test::WWW::Selenium->new( host => "localhost", 
                                    port => 4444, 
                                    browser => "*firefox", 
                                    browser_url => "http://www.google.com/" );

$sel->open_ok("/");
$sel->is_text_present_ok("Google");

