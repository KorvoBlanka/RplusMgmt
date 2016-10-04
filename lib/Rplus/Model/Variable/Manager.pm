package Rplus::Model::Variable::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Variable;

sub object_class { 'Rplus::Model::Variable' }

__PACKAGE__->make_manager_methods('variables');

1;

