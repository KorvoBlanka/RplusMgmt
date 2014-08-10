package Rplus::Model::RuntimeParam::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::RuntimeParam;

sub object_class { 'Rplus::Model::RuntimeParam' }

__PACKAGE__->make_manager_methods('_runtime_params');

1;

