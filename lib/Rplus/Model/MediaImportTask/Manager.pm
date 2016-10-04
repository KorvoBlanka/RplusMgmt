package Rplus::Model::MediaImportTask::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::MediaImportTask;

sub object_class { 'Rplus::Model::MediaImportTask' }

__PACKAGE__->make_manager_methods('media_import_tasks');

1;

