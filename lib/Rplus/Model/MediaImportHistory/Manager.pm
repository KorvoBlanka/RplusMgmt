package Rplus::Model::MediaImportHistory::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::MediaImportHistory;

sub object_class { 'Rplus::Model::MediaImportHistory' }

__PACKAGE__->make_manager_methods('media_import_history');

1;

