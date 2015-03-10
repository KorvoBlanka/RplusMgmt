package Rplus::Model::Option::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Option;

sub object_class { 'Rplus::Model::Option' }

__PACKAGE__->make_manager_methods('options');

1;

