package Rplus::DB::Object;

use Rplus::Modern;

use base qw(Rose::DB::Object);

use Rplus::DB;
use Rplus::DB::Object::Metadata;

use Rose::DB::Object::Helpers qw(as_tree column_value_pairs);

#
# Class methods
#

sub init_db { Rplus::DB->new_or_cached }

sub meta_class { 'Rplus::DB::Object::Metadata' }

#
# Additional operators
#
$Rose::DB::Object::QueryBuilder::Op_Map{'@@'} = '@@';
$Rose::DB::Object::QueryBuilder::Op_Map{'&&'} = '&&';

1;
