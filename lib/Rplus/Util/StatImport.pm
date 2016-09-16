package Rplus::Util::StatImport;

use Rplus::Modern;

use Rplus::Model::Realty::Manager;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::RealtyType::Manager;
use Rplus::Model::MediaImportStatistic;
use Rplus::Model::MediaImportStatistic::Manager;

use Rplus::Util::Geo;
use Rplus::Util::Image;

use Data::Dumper;

use Exporter qw(import);

sub save_import_statistic {
    my ($id, $stat_count) = @_;
    my $now_dt = DateTime->now(time_zone => "+1000");

    Rplus::Model::MediaImportStatistic->new(media_id => $id,
                                        add_date => $now_dt,
                                        all_ad => $stat_count->{count_all_ad},
                                        new_ad => $stat_count->{count_new_ad},
                                        update_ad => $stat_count->{count_update_ad},
                                        errors_ad => $stat_count->{count_error_ad})->save;
    say "New statistic Data";
}

1;
