package Rplus::Model::QueryCache::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::QueryCache;

sub object_class { 'Rplus::Model::QueryCache' }

__PACKAGE__->make_manager_methods('_query_cache');

1;

