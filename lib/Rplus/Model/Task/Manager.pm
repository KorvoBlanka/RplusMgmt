package Rplus::Model::Task::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Task;

sub object_class { 'Rplus::Model::Task' }

__PACKAGE__->make_manager_methods('tasks');

1;

