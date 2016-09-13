package Rplus::Model::HistoryRecord::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::HistoryRecord;

sub object_class { 'Rplus::Model::HistoryRecord' }

__PACKAGE__->make_manager_methods('history_records');

1;

