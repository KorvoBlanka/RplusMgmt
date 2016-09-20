package Rplus::Model::MediaImportError::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::MediaImportError;

sub object_class { 'Rplus::Model::MediaImportError' }

__PACKAGE__->make_manager_methods('media_import_errors');

1;

