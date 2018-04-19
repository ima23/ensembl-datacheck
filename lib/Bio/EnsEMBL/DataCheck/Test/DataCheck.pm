=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the 'License');
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an 'AS IS' BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=head1 NAME
Bio::EnsEMBL::DataCheck::Test::DataCheck

=head1 DESCRIPTION
Collection of Test::More style tests for Ensembl data.

=cut

package Bio::EnsEMBL::DataCheck::Test::DataCheck;

use warnings;
use strict;
use feature 'say';

use Test::Builder::Module;
# use Test::Deep::NoTest;

our $VERSION = 1.00;
our @ISA     = qw(Test::Builder::Module);
our @EXPORT  = qw(
  is_rows cmp_rows is_rows_zero is_rows_nonzero 
  row_totals row_subtotals
  fk
);

use constant MAX_DIAG_ROWS => 10;

my $CLASS = __PACKAGE__;

sub _query {
  my ( $dbc, $sql ) = @_;

  $dbc = $dbc->dbc() if $dbc->can('dbc');

  my ($count, $rows);

  if ( index( uc($sql), "SELECT COUNT" ) != -1 &&
       index( uc($sql), "GROUP BY" ) == -1 )
  {
    $count = $dbc->sql_helper()->execute_single_result( -SQL => $sql );
  } else {
    $rows  = $dbc->sql_helper()->execute( -SQL => $sql );
    $count = scalar @$rows;
  }

  return ($count, $rows);
}

=head2 Counting Database Rows

Tests for counting rows are among the most basic (and most useful) ways
to check whether data is as expected.

=over 4

=item B<is_rows>

  is_rows($dbc, $sql, $expected, $test_name);

This runs an SQL statement C<$sql> against the database connection C<$dbc>.
If the number of rows matches C<$expected>, the test will pass. The SQL
statement can be an explicit C<COUNT(*)> (recommended for speed) or a
C<SELECT> statement whose rows will be counted. The database connection
can be a Bio::EnsEMBL::DBSQL::DBConnection or DBAdaptor object.

C<$test_name> is a very short description of the test that will be printed
out; it is optional, but we B<very> strongly encourage its use.

=cut

sub is_rows {
  my ( $dbc, $sql, $expected, $name ) = @_;

  my ( $count, undef ) = _query( $dbc, $sql );

  my $tb = $CLASS->builder;

  return $tb->is_eq( $count, $expected, $name );
}

=item B<cmp_rows>

  cmp_rows($dbc, $sql, $operator, $expected, $test_name);

This runs an SQL statement C<$sql> against the database connection C<$dbc>.
If the number of rows is C<$operator $expected>, the test will pass. The
operator can be any valid Perl operator, e.g. '<', '!='. The SQL
statement can be an explicit C<COUNT(*)> (recommended for speed) or a
C<SELECT> statement whose rows will be counted. The database connection
can be a Bio::EnsEMBL::DBSQL::DBConnection or DBAdaptor object.

C<$test_name> is a very short description of the test that will be printed
out; it is optional, but we B<very> strongly encourage its use.

=cut

sub cmp_rows {
  my ( $dbc, $sql, $operator, $expected, $name ) = @_;

  my ( $count, undef ) = _query( $dbc, $sql );

  my $tb = $CLASS->builder;

  return $tb->cmp_ok( $count, $operator, $expected, $name );
}

=item B<is_rows_zero>

  is_rows_zero($dbc, $sql, $test_name, $diag_msg);

This runs an SQL statement C<$sql> against the database connection C<$dbc>.
If the number of rows is zero, the test will pass. The SQL statement can be
an explicit C<COUNT(*)> or a C<SELECT> statement whose rows will be counted.
In the latter case, rows which are returned will be printed as diagnostic
messages; we strongly advise providing a meaningful C<$diag_msg>, otherwise
a generic one will be displayed. A maximum of 10 messages will be displayed
The database connection can be a Bio::EnsEMBL::DBSQL::DBConnection or
DBAdaptor object.

C<$test_name> is a very short description of the test that will be printed
out; it is optional, but we B<very> strongly encourage its use.

=cut

sub is_rows_zero {
  my ( $dbc, $sql, $name, $diag_msg ) = @_;

  my ( $count, $rows ) = _query( $dbc, $sql );

  my $tb = $CLASS->builder;

  if (defined $rows) {
    $diag_msg ||= 'Unexpected data';

    my $counter = 0;
    foreach my $row ( @$rows ) {
      $tb->diag( "$diag_msg (" . join(', ', @$row) . ")" );
      last if ++$counter == MAX_DIAG_ROWS;
    }

    if ($count > MAX_DIAG_ROWS) {
      $dbc = $dbc->dbc() if $dbc->can('dbc');
      my $dbname = $dbc->dbname;
      $tb->diag( 'Reached limit for number of diagnostic messages' );
      $tb->diag( "Execute $sql against $dbname to see all results" );
    }
  }

  return $tb->is_eq( $count, 0, $name );
}

=item B<is_rows_nonzero>

  is_rows_nonzero($dbc, $sql, $test_name);

Convenience method, equivalent to cmp_rows($dbc, $sql, '>', 0, $test_name).

=cut

sub is_rows_nonzero {
  my ( $dbc, $sql, $name ) = @_;

  my ( $count, undef ) = _query( $dbc, $sql );

  my $tb = $CLASS->builder;

  return $tb->cmp_ok( $count, '>', 0, $name );
}

=head2 Comparing Database Rows

=item B<row_totals>
=item B<row_subtotals>

Rather than compare a row count with an expected value, we might want to
compare with a count from another database. The simplest scenario is when
there's a single total to compare.

  row_totals($dbc1, $dbc2, $sql, $min_proportion, $test_name);

This runs an SQL statement C<$sql> against both database connections C<$dbc1>
and C<$dbc2>. The SQL statement can be an explicit C<COUNT(*)> (recommended
for speed) or a C<SELECT> statement whose rows will be counted.
The database connection can be a Bio::EnsEMBL::DBSQL::DBConnection or
DBAdaptor object. It is assumed that C<$dbc1> is the connection for the new or
'primary' database, and that C<$dbc2> is for the old, or 'secondary' database.

By default, the test only fails if the counts are exactly the same. To allow
for some wiggle room, C<$min_proportion> can be used to define the minimum
acceptable difference between the counts. For example, a value of 0.75 means
that the count for C<$dbc2> must not be less that 75% of the count for C<$dbc1>.

C<$test_name> is a very short description of the test that will be printed
out; it is optional, but we B<very> strongly encourage its use.

A slightly more complex case is when you want to compare counts within
categories, i.e. with an SQL query that uses a GROUP BY statement.

  row_subtotals($dbc1, $dbc2, $sql, $min_proportion, $test_name);

In this case the SQL statement must return only two columns, the subtotal
category and the count, e.g. C<SELECT biotype, COUNT(*) FROM gene GROUP BY biotype>.
If any subtotals are lower than expected the test will fail, and the details
will be provided in a diagnostic message.

=cut

# flip logic, assume first dbc is always primary or new...

sub row_totals {
  my ( $dbc1, $dbc2, $sql, $min_proportion, $name ) = @_;
  $min_proportion = 1 if ! defined $min_proportion;

  my ( $count1, undef ) = _query( $dbc1, $sql );
  my ( $count2, undef ) = _query( $dbc2, $sql );

  my $tb = $CLASS->builder;

  return $tb->cmp_ok( $count2 * $min_proportion, '<=', $count1, $name );
}

sub row_subtotals {
  my ( $dbc1, $dbc2, $sql, $min_proportion, $name ) = @_;
  $min_proportion = 1 if ! defined $min_proportion;

  unless ($sql =~ /^SELECT\s+[^,]+\s*,\s*COUNT[^,]+FROM.+GROUP\s+BY/) {
    die "Invalid SQL statement for subtotals. Must select a single column first, then a count.\n($sql)";
  }

  my ( undef, $rows1 ) = _query( $dbc1, $sql );
  my ( undef, $rows2 ) = _query( $dbc2, $sql );

  my $tb = $CLASS->builder;

  my %subtotals1 = map { $_->[0] => $_->[1] } @$rows1;
  my %subtotals2 = map { $_->[0] => $_->[1] } @$rows2;

  my $ok = 1;

  # Note that there may be categories in %subtotals1 that aren't in
  # %subtotals2; but we don't care about them, we only need to know if
  # things have disappeared or changed, new stuff is fine.
  foreach my $category (keys %subtotals2) {
    $subtotals1{$category} = 0 unless exists $subtotals1{$category};

    if ($subtotals2{$category} * $min_proportion > $subtotals1{$category}) {
      $ok = 0;
      my $diag_msg =
        "Lower count than expected for $category.\n".
        $subtotals1{$category} . ' < ' . $subtotals2{$category} . ' * ' . $min_proportion*100 . '%';
      
      $tb->diag( $diag_msg );
    }
  }

  return $tb->ok( $ok, $name );
}


=head2 fk

  Arg [1]    : Bio::EnsEMBL::DBSQL::DBConnection or DBAdaptor
  Arg [2]    : "from" table
  Arg [3]    : "from" column
  Arg [4]    : "to" table
  Arg [5]    : "to" column
  Arg [6]    : (optional) set to 1 to check in both directions
  Arg [7]    : (optional) SQL constraint
  Arg [8]    : (optional) name for test
  Example    : fk($dba,"gene","canonical_transcript_id",
                 "transcript","transcript_id",0,"",
                 "Check if canonical transcripts exist");
  Description: Check for foreign keys between 2 tables 
  Returntype : none
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub fk {
  my ( $dba, $table1, $col1, $table2, $col2, $both_ways, $constraint, $name ) =
    @_;

  $col2 ||= $col1;
  $both_ways ||= 0;
  my $sql_left =
    qq/SELECT COUNT(*) FROM $table1 
    LEFT JOIN $table2 ON $table1.$col1 = $table2.$col2 
    WHERE $table2.$col2 IS NULL/;

  if ($constraint) {
    $sql_left .= " AND $constraint";
  }

  rows_zero( $dba,
                    $sql_left, (
                      $name ||
"Checking for values in ${table1}.${col1} not found in ${table2}.${col2}" ) );

  if ($both_ways) {

    my $sql_right =
      qq/SELECT COUNT(*) FROM $table2 
      LEFT JOIN $table1 
      ON $table2.$col2 = $table1.$col1 
      WHERE $table1.$col1 IS NULL/;

    if ($constraint) {
      $sql_right .= " AND $constraint";
    }

    rows_zero( $dba,
                      $sql_right, (
                        $name ||
"Checking for values in ${table2}.${col2} not found in ${table1}.${col1}" ) );

  }

  return;
} ## end sub fk

1;
