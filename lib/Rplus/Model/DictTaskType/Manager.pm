package Rplus::Model::DictTaskType::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::DictTaskType;

sub object_class { 'Rplus::Model::DictTaskType' }

__PACKAGE__->make_manager_methods('dict_task_types');

1;

