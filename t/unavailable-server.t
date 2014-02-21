# vim: ft=perl
use Test::More;
use strict;
use warnings;
use FindBin qw($Bin);
if ( $Bin =~ /(.*)/ ) {
    $Bin = $1;
}

## Test that failover happens when a server is unavailable.

use DBI;
use DBD::SQLite;
use DBD::Multi;
use Data::Dumper;
use Sys::SigAction qw( timeout_call );

eval { require DBD::Pg; };
if ( $@ ) {  plan skip_all => 'DBD::Pg unavailable'; exit; }

plan tests => 7;
pass 'DBD::Pg is installed';

my @PG_CONNECT = ('dbi:Pg:dbname=fake;host=192.0.2.1', 'fakeuser','fakepass') ;
my $SQ_TABLE = "$Bin/one.db";
my @SQ_CONNECT = ("dbi:SQLite:$SQ_TABLE");

unlink( $SQ_TABLE );

# Set up the first DB with a value of 1
my $dbh_1 = DBI->connect( @SQ_CONNECT );
is $dbh_1->do("CREATE TABLE multi(id int)"), '0E0', 'do create successful';
is($dbh_1->do("INSERT INTO multi VALUES(1)"), 1, 'insert via do works');

## Verify a normal connect attempt to the non-existant pg server fails:

ok(
    timeout_call(
        5,
        sub {
            my $ctest = DBI->connect(@PG_CONNECT);
        }
    ),
    'Direct connection timed out' );

my $c = DBI->connect('DBI:Multi:', undef, undef, {
    dsns => [
        1 =>  \@PG_CONNECT,
        50 => \@SQ_CONNECT,
    ],
});

ok( !timeout_call( 0, sub{ sleep 2 } ), "Timeout 0 should never time out" );

my $val;
ok(
    # Note:  Since DBD::Multi is using timeout_call, and since you can't nest
    #calls to timeout_call, the timeout period here is really irrelevant as long
    #as Multi is doing what it should.  What's important is that a value is
    #eventually returned.  The only reason timeout_call is used at all is in
    #case Multi turns out to be broken.

    !timeout_call( 10,
                   sub { $val = $c->selectrow_array("SELECT id FROM multi") }
    ),
    "Value should have been returned" );

is($val, 1, "Query failed over to the second DB");
unlink( $SQ_TABLE );
