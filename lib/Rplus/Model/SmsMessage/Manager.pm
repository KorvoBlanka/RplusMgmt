package Rplus::Model::SmsMessage::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::SmsMessage;

sub object_class { 'Rplus::Model::SmsMessage' }

__PACKAGE__->make_manager_methods('sms_messages');

1;

