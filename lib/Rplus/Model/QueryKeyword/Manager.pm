package Rplus::Model::QueryKeyword::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::QueryKeyword;

sub object_class { 'Rplus::Model::QueryKeyword' }

__PACKAGE__->make_manager_methods('query_keywords');

1;

