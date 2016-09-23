package Rplus::Model::MediaImportStatistic::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::MediaImportStatistic;

sub object_class { 'Rplus::Model::MediaImportStatistic' }

__PACKAGE__->make_manager_methods('media_import_statistic');

1;

