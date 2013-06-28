package TAEB::AI::Magus::Goal::EarlyExperience;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub met_when { TAEB->level >= 4 } # sleep resistance

1;

