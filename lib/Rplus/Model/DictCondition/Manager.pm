package Rplus::Model::DictCondition::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::DictCondition;

sub object_class { 'Rplus::Model::DictCondition' }

__PACKAGE__->make_manager_methods('dict_conditions');

1;

