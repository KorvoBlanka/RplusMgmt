package Rplus::Util::StatImport;

use Rplus::Modern;

use Rplus::Model::Realty::Manager;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::RealtyType::Manager;
use Rplus::Model::MediaImportStatistic;
use Rplus::Model::MediaImportStatistic::Manager;
use Rplus::Model::MediaImportError;
use Rplus::Model::MediaImportError::Manager;

use Rplus::Util::Geo;
use Rplus::Util::Image;

use Data::Dumper;

use Exporter qw(import);


sub save_import_statistic {
    my ($id, $stat_count) = @_;
    my $now_dt = DateTime->now(time_zone => "local");

    my $temp=Rplus::Model::MediaImportStatistic->new(media_id => $id,
                                        add_date_start => $stat_count->{date_start},
                                        add_date_end => $now_dt,
                                        all_link => $stat_count->{count_all_ad},
                                        new_ad => $stat_count->{count_new_ad},
                                        update_ad => $stat_count->{count_update_ad},
                                        update_link => $stat_count->{count_update_link},
                                        errors_link => $stat_count->{count_error_ad})->save;


    for(my $i=0; $i<scalar @{$stat_count->{url_list}}; $i++){
        Rplus::Model::MediaImportError->new(
                                          id_import_stat => 0+$temp->{id},
                                          url => $stat_count->{url_list}->[$i],
                                          error_text => $stat_count->{error_list}->[$i])->save;
    }

    say "New statistic Data";
}

1;
