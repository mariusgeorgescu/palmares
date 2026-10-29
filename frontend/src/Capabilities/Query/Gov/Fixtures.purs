-- | Fixturile de citire, separate de `Mock.purs` ca acela să rămână doar cablaj.
-- |
-- | __Fiecare e un payload măsurat, nu inventat.__ Se obține interogând serviciul care rulează și se
-- | lipește aici neatins. Unde un array real e lung (top 10 DRep-i, 5 acțiuni care se închid), se
-- | păstrează primele câteva elemente — e tot date reale, doar mai puține rânduri. Ce __nu__ se
-- | taie: `participation_by_epoch` (20 de puncte, cât cere graficul) și cele două desfășurări de
-- | acțiuni, pentru că numărul lor de categorii e el însuși un fapt de verificat.
module Capabilities.Query.Gov.Fixtures
  ( statusFixture
  , dashboardFixture
  , drepExplorerFixture
  , drepDetailFixture
  , govActionListFixture
  , govActionDetailFixture
  , votesListFixture
  , searchFixture
  , formulasFixture
  , spoListFixture
  , committeeFixture
  , withdrawalListFixture
  , delegationListFixture
  , activityFixture
  , disputeDetailFixture
  , attestationDetailFixture
  , profileDetailFixture
  , profileListFixture
  , attestationListFixture
  , disputeListFixture
  ) where

-- | `GET /status` pe preprod, 2026-10-24. `epoch_params` e omis: niciun decodor nu-l citește încă,
-- | iar ecranul de Metodologie își va aduce propriul DTO.
statusFixture :: String
statusFixture =
  """
  { "network": "preprod"
  , "governance":
      { "epoch": 321
      , "slot": 137140009
      , "block_time": "2026-10-24T06:26:49Z"
      , "lag_seconds": 43
      , "is_ready": true
      , "source": "cardano-db-sync"
      }
  , "attest_lag_seconds": 0
  , "attestation":
      { "slot": 137140009
      , "kupo_tip_slot": 137140009
      , "lag_seconds": 0
      , "state": "following"
      , "last_sync_at": "2026-10-24T06:27:22.960784Z"
      , "is_ready": true
      , "policy_id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3"
      , "last_error": null
      , "source": "attest-sync/kupo"
      }
  , "drep_distr_epoch": 321
  , "amber_lag_seconds": 120
  , "ready_max_lag_seconds": 300
  , "metrics_as_of_epoch": 321
  }
  """

-- | `GET /pages/dashboard` pe preprod, 2026-10-25, cu parametrii impliciți (`top_limit` 10,
-- | `closing_soon_limit` 5, `epochs` 20).
-- |
-- | Două cifre din el merită citite împreună: `total_dreps` 294 și `active_dreps` 17 +
-- | `inactive_dreps` 187 = 204. Diferența de 90 sunt DRep-ii cu status `unknown`. De aceea linkul
-- | de pe dashboard spre listă poartă explicit `status=active&status=inactive`: altfel utilizatorul
-- | dă clic pe „204" și aterizează pe o listă de 294.
dashboardFixture :: String
dashboardFixture =
  """
  {
    "epoch": 321,
    "total_dreps": 294,
    "active_dreps": 17,
    "inactive_dreps": 187,
    "unknown_dreps": 90,
    "retired_dreps": 526,
    "power_epoch": 321,
    "drep_power_lovelace": 505754377083269,
    "always_abstain_lovelace": 432909247919877,
    "always_no_confidence_lovelace": 330754812982,
    "total_actions": 131,
    "actions_in_flight": 7,
    "treasury_requested_lovelace": 656466092110010,
    "treasury_enacted_lovelace": 0,
    "actions_by_type": [
      [
        "hard_fork_initiation",
        4
      ],
      [
        "info_action",
        17
      ],
      [
        "new_committee",
        8
      ],
      [
        "new_constitution",
        2
      ],
      [
        "no_confidence",
        2
      ],
      [
        "parameter_change",
        16
      ],
      [
        "treasury_withdrawals",
        82
      ]
    ],
    "actions_by_state": [
      [
        "dropped",
        6
      ],
      [
        "enacted",
        11
      ],
      [
        "expired",
        107
      ],
      [
        "proposed",
        7
      ],
      [
        "ratified",
        0
      ]
    ],
    "participation_by_epoch": [
      {
        "epoch": 302,
        "dreps_with_power": 169,
        "dreps_voted": 35,
        "votes_cast": 35,
        "participation_rate": 0.20710059171597633
      },
      {
        "epoch": 303,
        "dreps_with_power": 171,
        "dreps_voted": 16,
        "votes_cast": 16,
        "participation_rate": 0.0935672514619883
      },
      {
        "epoch": 304,
        "dreps_with_power": 171,
        "dreps_voted": 3,
        "votes_cast": 3,
        "participation_rate": 0.017543859649122806
      },
      {
        "epoch": 305,
        "dreps_with_power": 172,
        "dreps_voted": 1,
        "votes_cast": 1,
        "participation_rate": 0.005813953488372093
      },
      {
        "epoch": 306,
        "dreps_with_power": 173,
        "dreps_voted": 31,
        "votes_cast": 32,
        "participation_rate": 0.1791907514450867
      },
      {
        "epoch": 307,
        "dreps_with_power": 176,
        "dreps_voted": 11,
        "votes_cast": 13,
        "participation_rate": 0.0625
      },
      {
        "epoch": 308,
        "dreps_with_power": 176,
        "dreps_voted": 40,
        "votes_cast": 40,
        "participation_rate": 0.22727272727272727
      },
      {
        "epoch": 309,
        "dreps_with_power": 176,
        "dreps_voted": 4,
        "votes_cast": 4,
        "participation_rate": 0.022727272727272728
      },
      {
        "epoch": 310,
        "dreps_with_power": 177,
        "dreps_voted": 15,
        "votes_cast": 17,
        "participation_rate": 0.0847457627118644
      },
      {
        "epoch": 311,
        "dreps_with_power": 177,
        "dreps_voted": 0,
        "votes_cast": 0,
        "participation_rate": 0.0
      },
      {
        "epoch": 312,
        "dreps_with_power": 178,
        "dreps_voted": 7,
        "votes_cast": 13,
        "participation_rate": 0.03932584269662921
      },
      {
        "epoch": 313,
        "dreps_with_power": 181,
        "dreps_voted": 17,
        "votes_cast": 31,
        "participation_rate": 0.09392265193370165
      },
      {
        "epoch": 314,
        "dreps_with_power": 181,
        "dreps_voted": 1,
        "votes_cast": 1,
        "participation_rate": 0.0055248618784530384
      },
      {
        "epoch": 315,
        "dreps_with_power": 182,
        "dreps_voted": 2,
        "votes_cast": 2,
        "participation_rate": 0.01098901098901099
      },
      {
        "epoch": 316,
        "dreps_with_power": 182,
        "dreps_voted": 2,
        "votes_cast": 2,
        "participation_rate": 0.01098901098901099
      },
      {
        "epoch": 317,
        "dreps_with_power": 186,
        "dreps_voted": 17,
        "votes_cast": 18,
        "participation_rate": 0.0913978494623656
      },
      {
        "epoch": 318,
        "dreps_with_power": 187,
        "dreps_voted": 26,
        "votes_cast": 26,
        "participation_rate": 0.13903743315508021
      },
      {
        "epoch": 319,
        "dreps_with_power": 186,
        "dreps_voted": 24,
        "votes_cast": 24,
        "participation_rate": 0.12903225806451613
      },
      {
        "epoch": 320,
        "dreps_with_power": 185,
        "dreps_voted": 16,
        "votes_cast": 16,
        "participation_rate": 0.08648648648648649
      },
      {
        "epoch": 321,
        "dreps_with_power": 185,
        "dreps_voted": 9,
        "votes_cast": 9,
        "participation_rate": 0.04864864864864865
      }
    ],
    "top_dreps_by_power": [
      {
        "id": "drep1ygzlzlzj8r9c3zutlgh9ugqx958cwr6q704xtt9j5uf4lzsz9rwhm",
        "hex": "05f17c5238cb888b8bfa2e5e20062d0f870f40f3ea65acb2a7135f8a",
        "has_script": false,
        "status": "active",
        "is_active": true,
        "active_until_epoch": 324,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2025-07-14T05:02:00Z",
        "age_days": 468,
        "voting_power": 400644627419166,
        "voting_power_epoch": 321,
        "delegator_count": 19,
        "eligible_actions": 105,
        "votes_cast": 10,
        "participation_rate": 0.09523809523809523,
        "rationale_rate": 0.0,
        "open_actions_unvoted": 7,
        "last_vote_at": "2026-07-29T19:21:51Z",
        "as_of_epoch": 321
      },
      {
        "id": "drep1yg3j4dkpz3j0eh4e9d5l3uy43sf5ndz2wv4c2fywgdcu4wsjmj5wp",
        "hex": "232ab6c11464fcdeb92b69f8f0958c1349b44a732b85248e4371caba",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 296,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": "unreachable",
        "registered_at": "2026-01-20T12:15:56Z",
        "age_days": 277,
        "voting_power": 60594158706858,
        "voting_power_epoch": 321,
        "delegator_count": 417,
        "eligible_actions": 36,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      },
      {
        "id": "drep1ygnl9fjlz3pahx5vd2m6y4ya0562n8ttqzss9ncacu6l6pqwm2php",
        "hex": "27f2a65f1443db9a8c6ab7a2549d7d34a99d6b00a102cf1dc735fd04",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 199,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2024-11-09T09:41:55Z",
        "age_days": 715,
        "voting_power": 7264462090316,
        "voting_power_epoch": 321,
        "delegator_count": 5,
        "eligible_actions": 119,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      }
    ],
    "closing_soon": [
      {
        "id": "6989c68f04b7452c22de9c0b95f40960cc17fab73bc2365f51d46da31db2c75e#0",
        "bech32": "gov_action1dxyudrcykazjcgk7ns9etaqfvrxp074h80prvh6363k6x8djca0qqpx4v94",
        "type": "no_confidence",
        "title": null,
        "abstract": null,
        "anchor_status": "unreachable",
        "proposed_at": {
          "slot": 135501681,
          "epoch": 317,
          "time": "2026-10-05T07:21:21Z",
          "tx_hash": "6989c68f04b7452c22de9c0b95f40960cc17fab73bc2365f51d46da31db2c75e"
        },
        "expires_epoch": 324,
        "last_votable_epoch": 323,
        "lifecycle": {
          "state": "proposed",
          "ratified_epoch": null,
          "enacted_epoch": null,
          "expired_epoch": null,
          "dropped_epoch": null,
          "formula_id": "gov_action_state_v1"
        },
        "deposit": 1000000000,
        "return_address": "stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4",
        "treasury_amount": null,
        "votes_cast": 0
      },
      {
        "id": "e5d288b5ce81c2b04bba8b5d3d9a69ac9a078544022fd0ec123fa5717d6f23f0#0",
        "bech32": "gov_action1uhfg3dwws8ptqja63dwnmxnf4jdq0p2yqghapmqj87jhzlt0y0cqqauysd8",
        "type": "hard_fork_initiation",
        "title": null,
        "abstract": null,
        "anchor_status": "unreachable",
        "proposed_at": {
          "slot": 135504192,
          "epoch": 317,
          "time": "2026-10-05T08:03:12Z",
          "tx_hash": "e5d288b5ce81c2b04bba8b5d3d9a69ac9a078544022fd0ec123fa5717d6f23f0"
        },
        "expires_epoch": 324,
        "last_votable_epoch": 323,
        "lifecycle": {
          "state": "proposed",
          "ratified_epoch": null,
          "enacted_epoch": null,
          "expired_epoch": null,
          "dropped_epoch": null,
          "formula_id": "gov_action_state_v1"
        },
        "deposit": 1000000000,
        "return_address": "stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4",
        "treasury_amount": null,
        "votes_cast": 0
      }
    ]
  }
  """

-- | `GET /pages/drep-explorer?limit=4&order_by=voting_power&sort_order=desc` pe preprod,
-- | 2026-10-25.
-- |
-- | Trei fapte măsurate pe care ecranul trebuie să le respecte, și pe care fixtura le păstrează:
-- |
-- |   * `status_facets` însumează 820, iar `total` e 294. Facetele se numără fiecare cu propriul
-- |     predicat scos (semantică standard de facet), deci __nu se calculează procente din ele__;
-- |   * `anchor_facets` însumează 131: un DRep fără ancoră nu intră în nicio categorie;
-- |   * `power_buckets` __da__ însumează la 294, pentru că fiecare DRep cade în exact un bucket.
-- |     E singura desfășurare din care un procent are sens.
-- |
-- | `language_facets` are o cheie goală (`""`, 4 DRep-i): limba e un câmp liber din metadate, iar
-- | șirul gol e o valoare pe care o scrie cineva, nu absența valorii.
drepExplorerFixture :: String
drepExplorerFixture =
  """
  {
    "items": [
      {
        "id": "drep1ygzlzlzj8r9c3zutlgh9ugqx958cwr6q704xtt9j5uf4lzsz9rwhm",
        "hex": "05f17c5238cb888b8bfa2e5e20062d0f870f40f3ea65acb2a7135f8a",
        "has_script": false,
        "status": "active",
        "is_active": true,
        "active_until_epoch": 324,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2025-07-14T05:02:00Z",
        "age_days": 468,
        "voting_power": 400644627419166,
        "voting_power_epoch": 321,
        "delegator_count": 19,
        "eligible_actions": 105,
        "votes_cast": 10,
        "participation_rate": 0.09523809523809523,
        "rationale_rate": 0.0,
        "open_actions_unvoted": 7,
        "last_vote_at": "2026-07-29T19:21:51Z",
        "as_of_epoch": 321
      },
      {
        "id": "drep1yg3j4dkpz3j0eh4e9d5l3uy43sf5ndz2wv4c2fywgdcu4wsjmj5wp",
        "hex": "232ab6c11464fcdeb92b69f8f0958c1349b44a732b85248e4371caba",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 296,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": "unreachable",
        "registered_at": "2026-01-20T12:15:56Z",
        "age_days": 277,
        "voting_power": 60594158706858,
        "voting_power_epoch": 321,
        "delegator_count": 417,
        "eligible_actions": 36,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      },
      {
        "id": "drep1ygnl9fjlz3pahx5vd2m6y4ya0562n8ttqzss9ncacu6l6pqwm2php",
        "hex": "27f2a65f1443db9a8c6ab7a2549d7d34a99d6b00a102cf1dc735fd04",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 199,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2024-11-09T09:41:55Z",
        "age_days": 715,
        "voting_power": 7264462090316,
        "voting_power_epoch": 321,
        "delegator_count": 5,
        "eligible_actions": 119,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      },
      {
        "id": "drep1yfleuad6rwdgk5y640aa3d4jc3gdukyq5vcxc84lx8mlklcw50hva",
        "hex": "7f9e75ba1b9a8b509aabfbd8b6b2c450de5880a3306c1ebf31f7fb7f",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 297,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2026-03-18T10:32:09Z",
        "age_days": 221,
        "voting_power": 7009495872731,
        "voting_power_epoch": 321,
        "delegator_count": 1,
        "eligible_actions": 36,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      }
    ],
    "total": 294,
    "limit": 4,
    "offset": 0,
    "epoch": 321,
    "status_facets": [
      [
        "active",
        17
      ],
      [
        "inactive",
        187
      ],
      [
        "retired",
        526
      ],
      [
        "unknown",
        90
      ]
    ],
    "anchor_facets": [
      [
        "unreachable",
        51
      ],
      [
        "valid",
        50
      ],
      [
        "hash_mismatch",
        26
      ],
      [
        "invalid_schema",
        4
      ]
    ],
    "language_facets": [
      [
        "en-us",
        50
      ],
      [
        "",
        4
      ]
    ],
    "power_buckets": [
      {
        "lo": 0,
        "hi": 1,
        "count": 109
      },
      {
        "lo": 1,
        "hi": 1000000000,
        "count": 28
      },
      {
        "lo": 1000000000,
        "hi": 10000000000,
        "count": 53
      },
      {
        "lo": 10000000000,
        "hi": 100000000000,
        "count": 69
      },
      {
        "lo": 100000000000,
        "hi": 1000000000000,
        "count": 23
      },
      {
        "lo": 1000000000000,
        "hi": null,
        "count": 12
      }
    ]
  }
  """

-- | `GET /pages/drep/drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z` pe preprod,
-- | 2026-10-25. Ales dintre cei 294 pentru că e cazul __greu__: DRep script, cu ancoră validă, cu
-- | două referințe externe, cu voturi pe patru tipuri de acțiuni din șapte — adică exact ecranul pe
-- | care se vede dacă randarea unui document străin e făcută cu grijă.
-- |
-- | `power_by_epoch` e ultimele 20 de puncte din cele 94 reale. `top_delegators` sunt toți cinci,
-- | __inclusiv al cincilea, care are `lovelace: null`__: un delegator pentru care epoca nu are
-- | stake înregistrat (limitarea §8.3 din contractul API-ului). Fixtura de dinainte îi tăia, și
-- | exact de aceea a trecut testele și a căzut în browser pe serverul adevărat.
drepDetailFixture :: String
drepDetailFixture =
  """
  {
    "drep": {
      "id": "drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z",
      "hex": "763ef75661f0cd8c8fa159a79d79bfe8f9a76878bdaaff700598ee0e",
      "has_script": true,
      "status": "inactive",
      "is_active": false,
      "active_until_epoch": 189,
      "given_name": "Logical Mechanism dRep",
      "image_url": "https://www.logicalmechanism.io/img/fullLogo.png",
      "language": "en-us",
      "anchor_status": "valid",
      "registered_at": "2024-09-06T23:10:12Z",
      "age_days": 778,
      "voting_power": 5942176444940,
      "voting_power_epoch": 321,
      "delegator_count": 5,
      "eligible_actions": 120,
      "votes_cast": 1,
      "participation_rate": 0.008333333333333333,
      "rationale_rate": 0.0,
      "open_actions_unvoted": 7,
      "last_vote_at": "2024-09-06T23:22:48Z",
      "as_of_epoch": 321
    },
    "metrics": {
      "as_of_epoch": 321,
      "eligible_actions": 120,
      "votes_cast": 1,
      "open_actions_unvoted": 7,
      "participation_rate": 0.008333333333333333,
      "rationale_verified": 0,
      "rationale_inline": 0,
      "rationale_unverified": 0,
      "rationale_pending": 0,
      "rationale_absent": 1,
      "rationale_cip100_valid": 0,
      "rationale_rate": 0.0,
      "vote_latency_median_hours": 0.05444444444444444,
      "vote_latency_p90_hours": 0.05444444444444444,
      "vote_latency_sample": 1,
      "age_days": 778,
      "final_votes": {
        "yes": 1,
        "no": 0,
        "abstain": 0
      },
      "votes_by_type": [
        [
          "hard_fork_initiation",
          {
            "eligible_actions": 2,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "info_action",
          {
            "eligible_actions": 17,
            "votes_cast": 1,
            "yes": 1,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.058823529411764705
          }
        ],
        [
          "new_committee",
          {
            "eligible_actions": 7,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "new_constitution",
          {
            "eligible_actions": 1,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "no_confidence",
          {
            "eligible_actions": 1,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "parameter_change",
          {
            "eligible_actions": 11,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "treasury_withdrawals",
          {
            "eligible_actions": 81,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ]
      ],
      "formula_ids": [
        "participation_rate_v1",
        "rationale_rate_v1",
        "age_days_v1",
        "delegator_retention_rate_v1",
        "vote_latency_median_hours_v1",
        "votes_by_type_v1"
      ]
    },
    "delegator_stats": {
      "delegator_count": 5,
      "delegator_count_prev": 5,
      "delegators_retained": 5,
      "delegators_joined": 0,
      "delegators_left": 0,
      "delegator_retention_rate": 1.0,
      "window_epochs": 10
    },
    "power_by_epoch": [
      {
        "epoch": 302,
        "lovelace": 5889967679740,
        "delegator_count": 5
      },
      {
        "epoch": 303,
        "lovelace": 5874056067112,
        "delegator_count": 5
      },
      {
        "epoch": 304,
        "lovelace": 5874836087448,
        "delegator_count": 5
      },
      {
        "epoch": 305,
        "lovelace": 5879754429475,
        "delegator_count": 5
      },
      {
        "epoch": 306,
        "lovelace": 5883923005781,
        "delegator_count": 5
      },
      {
        "epoch": 307,
        "lovelace": 5888569602056,
        "delegator_count": 5
      },
      {
        "epoch": 308,
        "lovelace": 5893190135192,
        "delegator_count": 5
      },
      {
        "epoch": 309,
        "lovelace": 5897720675965,
        "delegator_count": 5
      },
      {
        "epoch": 310,
        "lovelace": 5901872333057,
        "delegator_count": 5
      },
      {
        "epoch": 311,
        "lovelace": 5906522519873,
        "delegator_count": 5
      },
      {
        "epoch": 312,
        "lovelace": 5910755571684,
        "delegator_count": 5
      },
      {
        "epoch": 313,
        "lovelace": 5910762282359,
        "delegator_count": 5
      },
      {
        "epoch": 314,
        "lovelace": 5910770233192,
        "delegator_count": 5
      },
      {
        "epoch": 315,
        "lovelace": 5914902920642,
        "delegator_count": 5
      },
      {
        "epoch": 316,
        "lovelace": 5919918376352,
        "delegator_count": 5
      },
      {
        "epoch": 317,
        "lovelace": 5924415104092,
        "delegator_count": 5
      },
      {
        "epoch": 318,
        "lovelace": 5928925649832,
        "delegator_count": 5
      },
      {
        "epoch": 319,
        "lovelace": 5933433550288,
        "delegator_count": 5
      },
      {
        "epoch": 320,
        "lovelace": 5937875560062,
        "delegator_count": 5
      },
      {
        "epoch": 321,
        "lovelace": 5942176444940,
        "delegator_count": 5
      }
    ],
    "top_delegators": [
      {
        "stake_address": "stake_test1uzrvw62pn24xw0yk8ksyuj6m4ezg6jgw9n4vjqktstjd5aspv59nv",
        "lovelace": 5912487235860,
        "delegated_at": {
          "slot": 69983290,
          "epoch": 165,
          "time": "2024-09-06T23:48:10Z",
          "tx_hash": "7215b4e94e30d1341b1c30f9defacfa9a583a2ef0973dcd3e2b862d9f5e386da"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1ur7sufjy8lfactkprnwl5x7mjn0ugajqg920n6uv4g7l68cra6p74",
        "lovelace": 11647105014,
        "delegated_at": {
          "slot": 71680542,
          "epoch": 169,
          "time": "2024-09-26T15:15:42Z",
          "tx_hash": "2d91ed34e62bcca5b1e80673044aec56ce2da17794be843a96e8784fcc97ca1a"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1uzl65wzu364hh0wxex94qsf5xkeaq2mnmc7xgnsnsjuqr4qruvxwu",
        "lovelace": 8863539868,
        "delegated_at": {
          "slot": 69981608,
          "epoch": 165,
          "time": "2024-09-06T23:20:08Z",
          "tx_hash": "46bd643c23eabbce70deebbf23127022f109f7813086b123b4cedca8f3d95983"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1upqt8jvd8d045a6gs2wkzt57rnx47s5ewz4un2l746r847g7hgw24",
        "lovelace": 180912096,
        "delegated_at": {
          "slot": 69981238,
          "epoch": 165,
          "time": "2024-09-06T23:13:58Z",
          "tx_hash": "fdd0e44251da1b0b6b6c9d8e92ad0010d3e13640f608ccf91c18278b9ab99861"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1uzyp0n0lqk65g9wae0uhn3fdzevww4u7w665w46wsdmeaysjvtvpu",
        "lovelace": null,
        "delegated_at": {
          "slot": 88520092,
          "epoch": 208,
          "time": "2025-04-09T12:54:52Z",
          "tx_hash": "bcfd8c71d322df7205013b0a5f5f418f80b733f95c37b31109557bfc3022317a"
        },
        "is_current": true
      }
    ],
    "updates": [
      {
        "kind": "updated",
        "at": {
          "slot": 69981800,
          "epoch": 165,
          "time": "2024-09-06T23:23:20Z",
          "tx_hash": "ebab27b88379f662d5bdcd2db7c0be391fd94674a889255411d540b6684e5c13"
        },
        "deposit": null,
        "anchor_url": "https://www.logicalmechanism.io/drepTestnet",
        "anchor_status": "valid"
      },
      {
        "kind": "registered",
        "at": {
          "slot": 69981012,
          "epoch": 165,
          "time": "2024-09-06T23:10:12Z",
          "tx_hash": "744fb092ab6d8a4d8ca8f66ea3c0abb6b9d49381205aa41c75c8597e91137948"
        },
        "deposit": 500000000,
        "anchor_url": null,
        "anchor_status": null
      }
    ],
    "anchor_content": {
      "given_name": "Logical Mechanism dRep",
      "objectives": "We want to provide expert consulting, comprehensive knowledge, and in-depth research into the future of Cardano.",
      "motivations": "We are a technical consulting company specializing in open-sourced decentralized applications for the everyday user. We know Cardano inwards and out.",
      "qualifications": "We are Plutus pioneers, dApp developers, stake pool operators, and open-source contributors. We know Cardano.",
      "image_url": "https://www.logicalmechanism.io/img/fullLogo.png",
      "payment_address": "addr_test1qrvnxkaylr4upwxfxctpxpcumj0fl6fdujdc72j8sgpraa9l4gu9er4t0w7udjvt2pqngddn6q4h8h3uv38p8p9cq82qav4lmp",
      "references": [
        {
          "label": "The Logical Mechanism Website",
          "uri": "https://www.logicalmechanism.io/"
        },
        {
          "label": "The Logical Mechanism GitHub",
          "uri": "https://github.com/logical-mechanism"
        }
      ]
    }
  }
  """

-- | `GET /gov-actions?limit=4&order_by=proposed_at&sort_order=desc` pe preprod, 2026-10-25.
govActionListFixture :: String
govActionListFixture =
  """
  {"items":[{"id":"04f23439388432a22b6830425d0a8114a168ac5ead2767fe122eb956e8593f44#0","bech32":"gov_action1qnergwfcsse2y2mgxpp96z5pzjsk3tz745nk0lsj96u4d6ze8azqqdc2a6v","type":"parameter_change","title":null,"abstract":null,"anchor_status":"unreachable","proposed_at":{"slot":136473457,"epoch":319,"time":"2026-10-16T13:17:37Z","tx_hash":"04f23439388432a22b6830425d0a8114a168ac5ead2767fe122eb956e8593f44"},"expires_epoch":326,"last_votable_epoch":325,"lifecycle":{"state":"proposed","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":null,"dropped_epoch":null,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4","treasury_amount":null,"votes_cast":43},{"id":"7277c327fafdfc877e6e6414016c04b04280ffb492518cfcc00a7fdcd19b6e5a#0","bech32":"gov_action1wfmuxfl6lh7gwlnwvs2qzmqykppgpla5jfgcelxqpflae5vmdedqqswtv74","type":"parameter_change","title":null,"abstract":null,"anchor_status":"unreachable","proposed_at":{"slot":135811038,"epoch":318,"time":"2026-10-08T21:17:18Z","tx_hash":"7277c327fafdfc877e6e6414016c04b04280ffb492518cfcc00a7fdcd19b6e5a"},"expires_epoch":325,"last_votable_epoch":324,"lifecycle":{"state":"proposed","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":null,"dropped_epoch":null,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4","treasury_amount":null,"votes_cast":2},{"id":"466c87a7002a39fadb8d6eb0d27c94e71a5f363cf9152cc7d8ca01315d82f458#0","bech32":"gov_action1gekg0fcq9gul4kudd6cdyly5uud97d3uly2je37cegqnzhvz73vqqp5s9yg","type":"treasury_withdrawals","title":null,"abstract":null,"anchor_status":"unreachable","proposed_at":{"slot":135688800,"epoch":317,"time":"2026-10-07T11:20:00Z","tx_hash":"466c87a7002a39fadb8d6eb0d27c94e71a5f363cf9152cc7d8ca01315d82f458"},"expires_epoch":324,"last_votable_epoch":323,"lifecycle":{"state":"proposed","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":null,"dropped_epoch":null,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4","treasury_amount":42000000,"votes_cast":1},{"id":"28dc44f2e6bdd8ca52cf14aebf935fe8dd4690ed65b7937170ab16718cca94e5#0","bech32":"gov_action19rwyfuhxhhvv55k0zjhtly6larw5dy8dvkmexuts4vt8rrx2jnjsq3c2j2m","type":"new_committee","title":null,"abstract":null,"anchor_status":"unreachable","proposed_at":{"slot":135506963,"epoch":317,"time":"2026-10-05T08:49:23Z","tx_hash":"28dc44f2e6bdd8ca52cf14aebf935fe8dd4690ed65b7937170ab16718cca94e5"},"expires_epoch":324,"last_votable_epoch":323,"lifecycle":{"state":"proposed","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":null,"dropped_epoch":null,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4","treasury_amount":null,"votes_cast":1}],"total":131,"limit":4,"offset":0,"next_cursor":null}  """

-- | `GET /pages/gov-action/90de87d4…%230` pe preprod, 2026-10-25 — o retragere de trezorerie de un
-- | milion de ADA, cu document CIP-108 valid.
-- |
-- | Trei fapte din el pe care ecranul trebuie să le spună cinstit:
-- |
-- |   * `ratio` e `null` deși s-au exprimat voturi — pragul se calculează pe putere, iar puterea de
-- |     ambele părți era zero. „0%" ar fi o afirmație despre rezultat;
-- |   * ciclul de viață are __și__ `expired_epoch` 304 __și__ `dropped_epoch` 305;
-- |   * `references` conține același link de două ori, iar `rationale` are peste 2.500 de
-- |     caractere. Amândouă se randează așa cum sunt: e documentul lor.
govActionDetailFixture :: String
govActionDetailFixture =
  """
  {"action":{"id":"90de87d46e6345118c01dc5ec701b4dce5621ffa3b1f98a3d55eb34e85da7392#0","bech32":"gov_action1jr0g04rwvdz3rrqpm30vwqd5mnjky8l68v0e3g74t6e5apw6wwfqq37hpcl","type":"treasury_withdrawals","title":"Rename the Chang 2 Hard Fork to the Plomin Hard Fork","abstract":"The Intersect Hard Fork Working Group proposes to name the next Cardano hard fork the “Plomin Hard Fork” in memory of Cardano community contributor Matthew Plomin.","anchor_status":"valid","proposed_at":{"slot":127034777,"epoch":297,"time":"2026-06-29T07:26:17Z","tx_hash":"90de87d46e6345118c01dc5ec701b4dce5621ffa3b1f98a3d55eb34e85da7392"},"expires_epoch":304,"last_votable_epoch":303,"lifecycle":{"state":"expired","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":304,"dropped_epoch":305,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uppy2gm2hqzkwc80em4mlat73j4jyqvzhclrvsu72g9xg4q2yweet","treasury_amount":1000000000000,"votes_cast":58},"tallies":[{"role":"drep","epoch":304,"yes_power":0,"no_power":1095127719870,"abstain_power":0,"yes_count":7,"no_count":2,"abstain_count":49,"ratio":0.0,"threshold":0.67,"threshold_param":"dvt_treasury_withdrawal","basis":"cast_votes_only","formula_id":"tally_cast_votes_v1"}],"withdrawals":[{"beneficiary":"stake_test1uppy2gm2hqzkwc80em4mlat73j4jyqvzhclrvsu72g9xg4q2yweet","amount":1000000000000,"enacted_at":null,"paid_heuristic":false}],"param_changes":[],"proposer":{"stake_address":"stake_test1uppy2gm2hqzkwc80em4mlat73j4jyqvzhclrvsu72g9xg4q2yweet","actions_count":2},"anchor_content":{"title":"Rename the Chang 2 Hard Fork to the Plomin Hard Fork","abstract":"The Intersect Hard Fork Working Group proposes to name the next Cardano hard fork the “Plomin Hard Fork” in memory of Cardano community contributor Matthew Plomin.","motivation":"There is a tradition of naming hard forks in memory of notable historical figures or significant contributors to the Cardano community. Naming this hard fork in memory of Matthew Plomin would memorialize his actions in life to selflessly support and contribute to the Cardano blockchain ecosystem.","rationale":"Renaming the “Second Chang Hard Fork” (Chang 2) to the Plomin Hard Fork, in memory of Cardano community contributor Matthew Plomin, reflects a natural progression of Cardano’s governance growth. Phil Chang was an employee of Input Output who made significant contributions to Cardano’s governance system to help transfer control and responsibility of the blockchain into the hands of the community. Matthew Plomin was an exemplar of the Cardano community, representing every individual who stands ready to pick up the torch and carry the ecosystem forward.\n\nMatthew was a much loved and respected member of the Cardano community. He passed unexpectedly on November 14th, 2024. Originally hailing from Indiana, USA; he earned a Bachelor of Science in Management degree from Purdue University where he met and married the love of his life, Jillian (Shaw). He went on to receive his Master of Business Administration Degree from George Washington University before joining the DWS Group (Deutsche Bank) and rising to the Head of the US Money Market Credit Research team. His expertise in the traditional finance world was instrumental in his journey to found $USDM, a Cardano-native stable coin pegged to the US Dollar and fully backed by dollar reserves.\n\nAs a Cardano community member, Matthew was always eager to learn more and excited to help others work through issues they encountered with their projects in the ecosystem. He taught himself how to mint native assets, experimenting with social games and helping Jillian to publish a book she authored in a serialized, token-based format. Seeing the need for a US Dollar-backed Stablecoin on Cardano, Matthew assembled a team that would become the Moneta project. Despite limited institutional backing during a market bottom, the community stepped up to champion him and their support helped his dream become a reality.\n\nMatthew leaves behind his wife, Jillian, their seven children, and the Moneta team. His legacy lives on through the work that he accomplished and the inspiration that he kindled in others. As a devout Roman Catholic Christian, Matthew lived out the “Golden Rule” to “do unto others as you would have them do unto you,” and the world is a better place for him being in it.","references":[{"label":"Vasil Hard Fork | Cardano Docs","uri":"https://docs.cardano.org/about-cardano/evolution/upgrades/vasil/"},{"label":"Chang upgrade #1 hard fork achieved! | Intersect MBO","uri":"https://www.intersectmbo.org/news/chang-upgrade-1-hard-fork-achieved"},{"label":"Vasil Hard Fork | Cardano Docs","uri":"https://docs.cardano.org/about-cardano/evolution/upgrades/vasil/"},{"label":"Chang upgrade #1 hard fork achieved! | Intersect MBO","uri":"https://www.intersectmbo.org/news/chang-upgrade-1-hard-fork-achieved"}]}}  """

-- | `GET /votes?limit=4&anchor_status=valid&order_by=cast_at&sort_order=desc` pe preprod,
-- | 2026-10-25.
-- |
-- | Filtrul pe ancoră validă e deliberat: din ~934 de voturi finale, __opt__ au un raționament
-- | verificat, iar fixtura trebuie să conțină cazul care se randează greu. Primul rând are
-- | `is_final: false` și `revote_count: 3` — un vot care a fost înlocuit, exact rândul pe care un
-- | ecran neatent l-ar număra ca încă unul.
votesListFixture :: String
votesListFixture =
  """
  {
    "items": [
      {
        "gov_action_id": "78a9aafe2e4e14828efa8cd5202fec08c996a9a00c7d56b317b6a95a80510db3#0",
        "gov_action_bech32": "gov_action10z564l3wfc2g9rh63n2jqtlvpryed2dqp374dvchk6544qz3pkesq7cqrfs",
        "gov_action_type": "parameter_change",
        "gov_action_title": null,
        "voter_role": "drep",
        "voter_id": "drep1y0lpypv3vgrg6scz4emwl5u9z5aq3m5z4m2x5zn0gguvu6sv8yks9",
        "voter_hot_hash": "fe12059162068d4302ae76efd385153a08ee82aed46a0a6f4238ce6a",
        "voter_name": null,
        "verdict": "yes",
        "cast_at": {
          "slot": 130847265,
          "epoch": 306,
          "time": "2026-08-12T10:27:45Z",
          "tx_hash": "952df62401da2dac25179da0ab55e0088bc164e37bdd13f5c2312e6229a26864"
        },
        "latency_hours": 112.63222222222223,
        "is_final": false,
        "is_first": true,
        "revote_count": 3,
        "anchor": {
          "url": "https://gateway.pinata.cloud/ipfs/bafkreigd4cspq46cuvm2vue4vlguldgpmkc572aykn56mghd23z2lgo6sm",
          "status": "valid",
          "cip100_valid": true
        },
        "voting_power": null,
        "voting_power_epoch": null
      },
      {
        "gov_action_id": "97d5bcc30ce59be99bd808345d99be8c18aa474abb2e5dcd9183b44f976ce12d#0",
        "gov_action_bech32": "gov_action1jl2mescvukd7nx7cpq69mxd73sv25362hvh9mnv3sw6yl9mvuyksqxdcx6k",
        "gov_action_type": "treasury_withdrawals",
        "gov_action_title": null,
        "voter_role": "constitutional_committee",
        "voter_id": "cc_cold1zdgf3h7sm6a8yhad66fpnr7r8m54n7l8umklrddxjhsxucgkudvrr",
        "voter_hot_hash": "e3a4c41d67592a1b8d87c62e5c5d73f7e8db836171945412d13f40f8",
        "voter_name": null,
        "verdict": "no",
        "cast_at": {
          "slot": 79926192,
          "epoch": 188,
          "time": "2024-12-31T01:43:12Z",
          "tx_hash": "41bcea0a3c79ca41fb4c3990f7bf060aec5786dba2dbe340d9f13673c9bf66fd"
        },
        "latency_hours": 346.5725,
        "is_final": true,
        "is_first": false,
        "revote_count": 2,
        "anchor": {
          "url": "https://hornan7.github.io/mike_hornan.jsonld",
          "status": "valid",
          "cip100_valid": true
        },
        "voting_power": null,
        "voting_power_epoch": null
      },
      {
        "gov_action_id": "acc84cdb5eae8fe33793a9329bdd73b51eef7d9a33f25352783015aaa63c16fe#0",
        "gov_action_bech32": "gov_action14nyyek674687xdun4yefhhtnk50w7lv6x0e9x5ncxq264f3uzmlqqn60xhh",
        "gov_action_type": "treasury_withdrawals",
        "gov_action_title": null,
        "voter_role": "constitutional_committee",
        "voter_id": "cc_cold1zdgf3h7sm6a8yhad66fpnr7r8m54n7l8umklrddxjhsxucgkudvrr",
        "voter_hot_hash": "e3a4c41d67592a1b8d87c62e5c5d73f7e8db836171945412d13f40f8",
        "voter_name": null,
        "verdict": "no",
        "cast_at": {
          "slot": 79926192,
          "epoch": 188,
          "time": "2024-12-31T01:43:12Z",
          "tx_hash": "41bcea0a3c79ca41fb4c3990f7bf060aec5786dba2dbe340d9f13673c9bf66fd"
        },
        "latency_hours": 346.56583333333333,
        "is_final": true,
        "is_first": false,
        "revote_count": 2,
        "anchor": {
          "url": "https://hornan7.github.io/mike_hornan.jsonld",
          "status": "valid",
          "cip100_valid": true
        },
        "voting_power": null,
        "voting_power_epoch": null
      },
      {
        "gov_action_id": "b52f02288e3ce8c7e57455522f4edd09c12797749e2db32098ecbe980b645d45#0",
        "gov_action_bech32": "gov_action1k5hsy2yw8n5v0et524fz7nkap8qj09m5nckmxgycajlfszmyt4zsqp0n7ft",
        "gov_action_type": "parameter_change",
        "gov_action_title": "Plutus V3 Cost Model Parameter Changes Prior to Chang#2",
        "voter_role": "constitutional_committee",
        "voter_id": "cc_cold1zdd8rutlfnjvrs97q56ht4ch4hn2mzsa23faq2n9eeqdfvgss2fuc",
        "voter_hot_hash": "104f3db4e905fd008396f53a6d035e290f97f6172d3792673b213956",
        "voter_name": null,
        "verdict": "yes",
        "cast_at": {
          "slot": 75624648,
          "epoch": 178,
          "time": "2024-11-11T06:50:48Z",
          "tx_hash": "0b16cf9a6f3e6b1c9fbe66b7f828786e89d8ef9dda16d53bc5cf37a08cee7bd3"
        },
        "latency_hours": 133.57361111111112,
        "is_final": true,
        "is_first": true,
        "revote_count": 1,
        "anchor": {
          "url": "https://raw.githubusercontent.com/Eastern-Cardano-Council/icc-ga-rationales/refs/heads/main/preprod/ga05/ga05-rationale.jsonld",
          "status": "valid",
          "cip100_valid": true
        },
        "voting_power": null,
        "voting_power_epoch": null
      }
    ],
    "total": 8,
    "limit": 4,
    "offset": 0
  }
  """

-- | `GET /search?q=logical&limit_per_group=3` pe preprod, 2026-10-25. Trei DRep-i, restul
-- | grupurilor goale — exact forma pe care ecranul trebuie să randeze fără să arate șase secțiuni
-- | vide.
searchFixture :: String
searchFixture =
  """
  {"query":"logical","total":3,"dreps":{"total":3,"items":[{"id":"drep1yvv7culkq0nqlgs6gtmkryuwp3lq49k5rhu6c7y2n2psu8g08rvmk","title":"Logical Mechanism dRep","subtitle":"19ec73f603e60fa21a42f761938e0c7e0a96d41df9ac788a9a830e1d","badges":["script"],"status":"retired","target":{"kind":"drep","id":"drep1yvv7culkq0nqlgs6gtmkryuwp3lq49k5rhu6c7y2n2psu8g08rvmk"}},{"id":"drep1yvmeer7fcwng5ea3v7cw2g2uq352sm58xtmaphp5vqvcxycrzszhz","title":"Logical Mechanism dRep","subtitle":"379c8fc9c3a68a67b167b0e5215c0468a86e8732f7d0dc3460198313","badges":["script"],"status":"unknown","target":{"kind":"drep","id":"drep1yvmeer7fcwng5ea3v7cw2g2uq352sm58xtmaphp5vqvcxycrzszhz"}},{"id":"drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z","title":"Logical Mechanism dRep","subtitle":"763ef75661f0cd8c8fa159a79d79bfe8f9a76878bdaaff700598ee0e","badges":["script"],"status":"inactive","target":{"kind":"drep","id":"drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z"}}]},"gov_actions":{"total":0,"items":[]},"spos":{"total":0,"items":[]},"committee_members":{"total":0,"items":[]},"profiles":{"total":0,"items":[]},"attestations":{"total":0,"items":[]}}  """

-- | Primele două din cele opt formule publicate de `GET /metrics/formulas`, cu SQL-ul __întreg__.
-- |
-- | Nu e tăiat, și ăsta e punctul: pagina de metodologie arată interogarea exact cum rulează, iar o
-- | fixtură cu SQL ciuntit ar demonstra contrariul în bundle-ul demo. Răspunsul e un array nud, nu
-- | un plic cu `items`.
formulasFixture :: String
formulasFixture =
  """
  [
    {
      "formula_id": "participation_rate_v1",
      "name": "Participation rate",
      "field": "participation_rate",
      "expression": "|actions_voted| / |actions_eligible|",
      "denominator": "distinct governance actions whose voting window closed before as_of_epoch, of a type the role may vote on in the action's protocol-version phase, overlapping a registered interval of the actor",
      "null_when": "eligible_actions = 0",
      "inputs": [
        "gov_action_proposal",
        "voting_procedure",
        "drep_registration",
        "epoch_param.protocol_major"
      ],
      "edge_cases": [
        "Conway bootstrap phase: a DRep could only vote on InfoAction, and the test is over the whole voting window rather than the proposing block",
        "re-votes collapsed to distinct actions; verdict = last vote, latency = first vote",
        "still-open actions excluded from the denominator and reported as open_actions_unvoted",
        "votes voided by DRep retirement still count as cast",
        "a registered DRep with zero delegated stake is still eligible: drep_distr membership is not part of the denominator"
      ],
      "sql_file": "participation_rate_v1.sql",
      "sql_object": null,
      "params": [
        "drep_hash_id",
        "as_of_epoch"
      ],
      "spec": "docs/spec/metrics.md#participation_rate_v1",
      "version": 1,
      "sql": "-- participation_rate_v1 — of the actions this DRep could have voted on, how many did it vote on.\n--\n-- Parameters are bound ONCE in the leading CTE, in the order resources/metric-formulas.json's\n-- `params` array names them: drep_hash_id, as_of_epoch. Every statement in this directory follows\n-- that shape, so a positional placeholder never has to be repeated and the names stay visible in\n-- the SQL.\n--\n-- A question mark may not appear ANYWHERE else in these files, comments included:\n-- postgresql-simple counts placeholders lexically over the whole statement, so a question mark in\n-- prose is read as a parameter and the query fails with \"N single chars, but M parameters\".\n-- UnitTests.MetricCatalog asserts the count per file so that lands as a clear failure.\n--\n-- The denominator is palmares.eligible_actions, not a re-derivation: registration overlap, the\n-- Conway bootstrap test and \"settled by as_of_epoch\" all live in that one function (D-15).\n-- `open_actions_unvoted` is reported separately because a still-open action is not a missed vote.\nWITH p AS (\n  SELECT ?::bigint AS drep_hash_id, ?::int AS as_of_epoch\n),\nelig AS (\n  SELECT e.gov_action_id, e.action_type\n  FROM p, palmares.eligible_actions(p.drep_hash_id, p.as_of_epoch) e\n),\nvoted AS (\n  SELECT DISTINCT v.gov_action_id\n  FROM palmares.vote v\n  JOIN elig e ON e.gov_action_id = v.gov_action_id\n  WHERE v.drep_voter_id = (SELECT drep_hash_id FROM p)\n),\nopen_unvoted AS (\n  -- The registration interval is required here, the same overlap test `elig` above applies through\n  -- palmares.eligible_actions. Without it every credential in the table reported every open action\n  -- as outstanding — including the 523 retired ones, which cannot legally vote on any of them, and\n  -- which were therefore served `eligible_actions: 0` beside `open_actions_unvoted: 11`.\n  SELECT a.gov_action_id\n  FROM palmares.action_window a\n  WHERE a.last_votable_epoch >= (SELECT as_of_epoch FROM p)\n    AND a.drep_votable\n    AND EXISTS (\n      SELECT 1 FROM palmares.drep_interval i\n      WHERE i.drep_hash_id = (SELECT drep_hash_id FROM p)\n        AND i.from_epoch <= a.last_votable_epoch\n        AND (i.to_epoch IS NULL OR i.to_epoch >= a.proposed_epoch)\n    )\n    AND NOT EXISTS (\n      SELECT 1 FROM palmares.vote v\n      WHERE v.drep_voter_id = (SELECT drep_hash_id FROM p)\n        AND v.gov_action_id = a.gov_action_id\n    )\n)\nSELECT\n  (SELECT count(*) FROM elig) AS eligible_actions,\n  (SELECT count(*) FROM voted) AS votes_cast,\n  -- NULL, not 0: a DRep with nothing it could have voted on has no participation rate. \"n/a\" and\n  -- \"0%\" are different statements about a person.\n  CASE WHEN (SELECT count(*) FROM elig) = 0 THEN NULL\n       ELSE (SELECT count(*) FROM voted)::float8 / (SELECT count(*) FROM elig) END AS participation_rate,\n  (SELECT count(*) FROM open_unvoted) AS open_actions_unvoted;\n"
    },
    {
      "formula_id": "rationale_rate_v1",
      "name": "Rationale rate",
      "field": "rationale_rate",
      "expression": "(rationale_verified + rationale_inline) / (rationale_verified + rationale_inline + rationale_absent)",
      "denominator": "the final votes on actions in the eligible set whose rationale we could actually assess: verified, inline, or demonstrably absent. Unverified and pending votes are excluded from both sides.",
      "null_when": "rationale_verified + rationale_inline + rationale_absent = 0, i.e. none of this actor's rationales could be assessed",
      "inputs": [
        "voting_procedure.voting_anchor_id",
        "voting_anchor",
        "off_chain_vote_data",
        "off_chain_vote_fetch_error"
      ],
      "edge_cases": [
        "five grades, not four: verified | inline | unverified | pending | absent",
        "inline is a data: URI, where the rationale IS the URL and hash verification is vacuous; counting it as missing would accuse an author who did publish one",
        "pending means db-sync has not attempted the fetch yet, which is not the author's failure",
        "unverified and pending are excluded from the DENOMINATOR, not counted as failures: measured on preprod, zero anchors on DRep votes are valid and 140 of the 237 unreachable ones are ipfs:// URIs our gateway list cannot fetch, so dividing by votes_cast would report our infrastructure's failure as 36 authors' negligence",
        "all five counters are published, so a consumer wanting another basis — an attachment rate, say — can compute it",
        "the five counters sum to votes_cast by construction, because the sample is the eligible set"
      ],
      "sql_file": "rationale_rate_v1.sql",
      "sql_object": null,
      "params": [
        "drep_hash_id",
        "as_of_epoch"
      ],
      "spec": "docs/spec/metrics.md#rationale_rate_v1",
      "version": 1,
      "sql": "-- rationale_rate_v1 — of the votes this DRep cast, how many carried a published rationale.\n--\n-- Params: drep_hash_id, as_of_epoch.\n--\n-- FIVE grades, not four (D-3), and the fifth is the one that matters for fairness:\n--   verified    the anchor was fetched and its hash matched\n--   inline      a `data:` URI: the rationale IS the URL, so there is nothing to fetch and hash\n--               verification is vacuous. preprod has real ones. Counting these as missing would\n--               accuse an author who did publish a rationale.\n--   unverified  a fetch was attempted and failed\n--   pending     an anchor is attached and db-sync has not tried yet\n--   absent      no anchor at all\n-- THE DENOMINATOR EXCLUDES WHAT WE COULD NOT ASSESS. The rate is\n--   (verified + inline) / (verified + inline + absent)\n-- so `unverified` and `pending` are out of BOTH sides. Rationale, and it is measured, not\n-- theoretical: across all 648 final DRep votes on preprod today there are ZERO `valid` anchors.\n-- 23 are unreachable, and network-wide 140 of the 237 unreachable anchors are `ipfs://` URIs that\n-- our db-sync's gateway list cannot fetch. Dividing by votes_cast would therefore publish\n-- \"essentially nobody on preprod writes rationales\" when the truth is \"our indexer cannot fetch\n-- IPFS\" — a statement about our infrastructure, printed as a judgement about 36 people.\n--\n-- An unreachable or not-yet-fetched anchor is evidence the author DID attach something and no\n-- evidence about its contents. Counting it as a failure is the same error the `inline` and\n-- `pending` grades exist to avoid; excluding it says \"we cannot tell\", which is true. When nothing\n-- can be assessed the rate is NULL — \"n/a\", not 0%.\n--\n-- All five counters are published regardless, so a consumer who wants a different basis (an\n-- attachment rate, say: (votes_cast - absent) / votes_cast) can compute it without us.\n--\n-- The five counters sum to votes_cast BY CONSTRUCTION, because `final` joins eligible_actions —\n-- the same denominator participation_rate uses. Taking every action the DRep ever voted on instead\n-- would let a vote on a still-open action into this sample while participation_rate excluded it,\n-- and the two rates would stop being comparable.\nWITH p AS (\n  SELECT ?::bigint AS drep_hash_id, ?::int AS as_of_epoch\n),\nelig AS (\n  SELECT e.gov_action_id\n  FROM p, palmares.eligible_actions(p.drep_hash_id, p.as_of_epoch) e\n),\nfinal AS (\n  SELECT v.gov_action_id, v.voting_anchor_id\n  FROM palmares.vote v\n  JOIN elig e ON e.gov_action_id = v.gov_action_id\n  WHERE v.drep_voter_id = (SELECT drep_hash_id FROM p)\n    AND v.seq_last = 1\n),\ngraded AS (\n  SELECT\n    f.gov_action_id,\n    CASE\n      WHEN f.voting_anchor_id IS NULL THEN 'absent'\n      WHEN a.verdict = 'inline' THEN 'inline'\n      WHEN a.verdict = 'valid' THEN 'verified'\n      WHEN a.verdict = 'not_fetched' THEN 'pending'\n      ELSE 'unverified'\n    END AS grade,\n    a.cip100_valid\n  FROM final f\n  LEFT JOIN palmares.anchor a ON a.voting_anchor_id = f.voting_anchor_id\n)\nSELECT\n  count(*) FILTER (WHERE grade = 'verified') AS rationale_verified,\n  count(*) FILTER (WHERE grade = 'inline') AS rationale_inline,\n  count(*) FILTER (WHERE grade = 'unverified') AS rationale_unverified,\n  count(*) FILTER (WHERE grade = 'pending') AS rationale_pending,\n  count(*) FILTER (WHERE grade = 'absent') AS rationale_absent,\n  count(*) FILTER (WHERE cip100_valid IS TRUE) AS rationale_cip100_valid,\n  CASE WHEN count(*) FILTER (WHERE grade IN ('verified', 'inline', 'absent')) = 0 THEN NULL\n       ELSE count(*) FILTER (WHERE grade IN ('verified', 'inline'))::float8\n            / count(*) FILTER (WHERE grade IN ('verified', 'inline', 'absent')) END AS rationale_rate\nFROM graded;\n"
    }
  ]
  """

-- | `GET /spos?limit=5`, măsurat 2026-10-25 pe preprod sincronizat (epoca 321).
-- |
-- | Toate cele 511 rânduri au `ticker` și `participation_rate` `null`; cele cinci de aici nu sunt
-- | alese ca să fie comode, ci sunt primele cinci. Vezi `SpoRow` pentru de ce.
-- |
-- | `limit` din plic e numărul de rînduri de aici, nu cel din cererea cu care au fost culese:
-- | altfel fixtura ar descrie un răspuns imposibil — „limita 200, șase rînduri, total 83" —
-- | iar paginatorul ar deduce din el că paginile mai adânci sînt refuzate.
spoListFixture :: String
spoListFixture =
  """
{
  "items": [
    {
      "pool_id": "pool1945cfqzmy2qe2z59mfdwm7jwqtucncfee5xkd8f4wu97zr8xuys",
      "ticker": null,
      "voting_power": 488729208474515,
      "voting_power_epoch": 321,
      "delegator_count": 5,
      "votes_cast": 8,
      "participation_rate": null
    },
    {
      "pool_id": "pool1sh4cddrln788xmnjnsqhdwj9e7th3c3ck3zjk7ny9znwj44t8he",
      "ticker": null,
      "voting_power": 293919746779515,
      "voting_power_epoch": 321,
      "delegator_count": 7,
      "votes_cast": 3,
      "participation_rate": null
    },
    {
      "pool_id": "pool18svpptnxfctewpx7ntnmlazy4w9cr24f4rcq8smkvpggw600ql4",
      "ticker": null,
      "voting_power": 189419869189615,
      "voting_power_epoch": 321,
      "delegator_count": 3,
      "votes_cast": 8,
      "participation_rate": null
    },
    {
      "pool_id": "pool1kxtrz8evgdrwwrdajhwweng6k8eysjvqgn59r8a5wkqw6rlnvv6",
      "ticker": null,
      "voting_power": 189414245806748,
      "voting_power_epoch": 321,
      "delegator_count": 5,
      "votes_cast": 8,
      "participation_rate": null
    },
    {
      "pool_id": "pool1nmfr5j5rnqndprtazre802glpc3h865sy50mxdny65kfgf3e5eh",
      "ticker": null,
      "voting_power": 48927508984815,
      "voting_power_epoch": 321,
      "delegator_count": 326,
      "votes_cast": 2,
      "participation_rate": null
    }
  ],
  "total": 511,
  "limit": 5,
  "offset": 0
}
"""

-- | `GET /committee`, măsurat 2026-10-25. Trei membri, cvorum 2/3, toți cu cheia fierbinte
-- | autorizată și niciunul demisionat — adică exact cazul în care ecranul trebuie să arate că
-- | `resigned_at` lipsind e normalul, nu o lipsă de date.
committeeFixture :: String
committeeFixture =
  """
{
  "quorum_numerator": 2,
  "quorum_denominator": 3,
  "established_by": "bbfa303aa35d19919934fb5fe36b174609a0c1dfb47a546ccd6ea58aa752e2aa#0",
  "epoch": 321,
  "members": [
    {
      "cold_hash": "615b54137e73f090d2dddb04317bee41624f4013e5cfe4a5efa76d76",
      "cold_bech32": "cc_cold1zds4k4qn0eelpyxjmhdsgvtmaeqkyn6qz0jule99a7nk6asezxvlu",
      "hot_hash": "5bfa7d850280c54110534065fa91a3635bbcc0eadc69c5c792c35e1e",
      "expiration_epoch": 372,
      "status": "active",
      "votes_cast": 6,
      "authorized_at": {
        "slot": 96856972,
        "epoch": 228,
        "time": "2025-07-15T00:42:52Z",
        "tx_hash": "bb70cd05900c3057688ddc9ed90189fba19d53ec0fe82f75532a2183afcb45ca"
      },
      "resigned_at": null
    },
    {
      "cold_hash": "e36d5e45b277bff4962d6c63be2375af8e68e558e6a373137a0ad6f2",
      "cold_bech32": "cc_cold1z03k6hj9kfmmlayk94kx803rwkhcu689trn2xucn0g9ddusykdhpl",
      "hot_hash": "26648e2c6bc4e4863a373bd28d480b2eb788922545e1df357e76a3d2",
      "expiration_epoch": 372,
      "status": "active",
      "votes_cast": 6,
      "authorized_at": {
        "slot": 96856972,
        "epoch": 228,
        "time": "2025-07-15T00:42:52Z",
        "tx_hash": "772a5039051d06c9e75d2871a81e8c9768f59c340ea9566c83975eb29594194c"
      },
      "resigned_at": null
    },
    {
      "cold_hash": "e883ad4599af7b01fe9d01c92bfa405151226db53982931d445b4a96",
      "cold_bech32": "cc_cold1z05g8t29nxhhkq07n5quj2l6gpg4zgndk5uc9ycag3d549svk3hyp",
      "hot_hash": "19ebff7033fe1c1f9cd2b346f2c9b0d7ff28b1527ebed1cc071155b4",
      "expiration_epoch": 372,
      "status": "active",
      "votes_cast": 6,
      "authorized_at": {
        "slot": 96856972,
        "epoch": 228,
        "time": "2025-07-15T00:42:52Z",
        "tx_hash": "2c6f3437b2f6b662375677408c318854baad0d85798e5525aa38ac52cdd1f3ae"
      },
      "resigned_at": null
    }
  ]
}
"""

-- | `GET /treasury-withdrawals`, măsurat 2026-10-25. Șase rînduri din 83: două cu titlu și patru
-- | fără, pentru că 80 din 83 n-au titlu. Niciunul nu e adoptat — pe preprod nu s-a plătit
-- | niciodată din trezorerie — deci `enacted_epoch` și `enacted_at` sînt `null` peste tot.
-- |
-- | `limit` din plic e numărul de rînduri de aici, nu cel din cererea cu care au fost culese:
-- | altfel fixtura ar descrie un răspuns imposibil — „limita 200, șase rînduri, total 83" —
-- | iar paginatorul ar deduce din el că paginile mai adânci sînt refuzate.
withdrawalListFixture :: String
withdrawalListFixture =
  """
{
  "items": [
    {
      "gov_action_id": "372d688faa77e146798b581b322c0f2981a9023764736ade5d12e0e4e796af8c#0",
      "gov_action_title": "Rename the Chang 2 Hard Fork to the Plomin Hard Fork",
      "beneficiary": "stake_test1uppy2gm2hqzkwc80em4mlat73j4jyqvzhclrvsu72g9xg4q2yweet",
      "amount": 1000000000000,
      "enacted_epoch": null,
      "enacted_at": null,
      "paid_heuristic": false
    },
    {
      "gov_action_id": "e1d1d4a310b4b500310e0433eeb70fb96b13ee91a7d05f605861a6b8618ef269#0",
      "gov_action_title": "Rename the Chang 2 Hard Fork to the Plomin Hard Fork",
      "beneficiary": "stake_test1uz9qfhmxg7x756qa5j64c90w0480qgcvs7qhvvv39w9072g9lc4dr",
      "amount": 1000000000000,
      "enacted_epoch": null,
      "enacted_at": null,
      "paid_heuristic": false
    },
    {
      "gov_action_id": "f74abd6f6f0430653ea736b7b714cc56f702288c7849ed6a79c870d342efb5ef#0",
      "gov_action_title": null,
      "beneficiary": "stake_test1upfpm2244k8jf00l357t3adp2hzfsuqrwqvleheqjj08uhswme5cn",
      "amount": 1000000000000,
      "enacted_epoch": null,
      "enacted_at": null,
      "paid_heuristic": false
    },
    {
      "gov_action_id": "97d5bcc30ce59be99bd808345d99be8c18aa474abb2e5dcd9183b44f976ce12d#0",
      "gov_action_title": null,
      "beneficiary": "stake_test1upfpm2244k8jf00l357t3adp2hzfsuqrwqvleheqjj08uhswme5cn",
      "amount": 987654321000,
      "enacted_epoch": null,
      "enacted_at": null,
      "paid_heuristic": false
    },
    {
      "gov_action_id": "acc84cdb5eae8fe33793a9329bdd73b51eef7d9a33f25352783015aaa63c16fe#0",
      "gov_action_title": null,
      "beneficiary": "stake_test1upfpm2244k8jf00l357t3adp2hzfsuqrwqvleheqjj08uhswme5cn",
      "amount": 123456789000,
      "enacted_epoch": null,
      "enacted_at": null,
      "paid_heuristic": false
    },
    {
      "gov_action_id": "c24c118d4247385aa748b707bd2c270baf53b23e8a547d726b1e1cb004cd8324#0",
      "gov_action_title": null,
      "beneficiary": "stake_test1upeqhnsgfnweefwfacf6dyzj5f94xqc6hfnjtrnh0ezu7qclg7p6m",
      "amount": 50000000000,
      "enacted_epoch": null,
      "enacted_at": null,
      "paid_heuristic": false
    }
  ],
  "total": 83,
  "limit": 6,
  "offset": 0
}
"""

-- | `GET /delegations`, măsurat 2026-10-25. Rînduri alese ca să acopere FORMELE, nu ca să
-- | arate bine: unul cu nume de DRep (18 din 200 au), unul fără sumă (43 din 200), unul către
-- | `always_abstain` — care nu e un DRep și nu are pagină — și trei obișnuite.
-- |
-- | `limit` din plic e numărul de rînduri de aici, nu cel din cererea cu care au fost culese:
-- | altfel fixtura ar descrie un răspuns imposibil — „limita 200, șase rînduri, total 83" —
-- | iar paginatorul ar deduce din el că paginile mai adânci sînt refuzate.
delegationListFixture :: String
delegationListFixture =
  """
{
  "items": [
    {
      "stake_address": "stake_test1ur3sr279lys8ry9wql40r4qcsrnfcgp70nrtjzezmuta0dqxd8k6h",
      "target": "drep1yf3yx7ptr0hks02d7k8c8xfq58jn68nje5emscvv7a9ngpqudkpdh",
      "target_name": "ADAtainment (Preprod)",
      "lovelace": 7088926872,
      "at": {
        "slot": 136541069,
        "epoch": 319,
        "time": "2026-10-17T08:04:29Z",
        "tx_hash": "cc06ad58fa4a3af8e7d34a732c4a738df6be0f5fe294d92474d35ee0dda7db5d"
      },
      "is_current": true
    },
    {
      "stake_address": "stake_test1uz2g27lray5puxeegyjmq6d7mkxdnmmr6ter0nnefpxl6kcf342dn",
      "target": "drep_always_abstain",
      "target_name": null,
      "lovelace": null,
      "at": {
        "slot": 137253690,
        "epoch": 321,
        "time": "2026-10-25T14:01:30Z",
        "tx_hash": "d86959c594c318c722088c3617498ece812f0817213033f2116751690322ee5b"
      },
      "is_current": true
    },
    {
      "stake_address": "stake_test1uzl34lkg3cggnsfvpag8eqecn524kpzuuh9n9tsxzvxgxygcwjha6",
      "target": "drep1ytax4rwzvdwamnu67j2uk9z00660lpzcvmlys6266l9kt5c262k7m",
      "target_name": null,
      "lovelace": 129734524921,
      "at": {
        "slot": 137024594,
        "epoch": 320,
        "time": "2026-10-22T22:23:14Z",
        "tx_hash": "ca9b62bdf1f53ac3440cb15965a19a91b701b664d4a9d0adad12f46e5537f875"
      },
      "is_current": true
    },
    {
      "stake_address": "stake_test17qcvvnfs02dlfry0c58kqq8hhs7069ulwlsm9l4s4ws0zdc70r9wx",
      "target": "drep1ygzqwwtgcewhzvxu942xufzl4pg7gnttw9h4e0agm30fnwsqcv00v",
      "target_name": null,
      "lovelace": 150000000,
      "at": {
        "slot": 136960123,
        "epoch": 320,
        "time": "2026-10-22T04:28:43Z",
        "tx_hash": "9be82418d26fedb8f8b88b665f6653eb7adc22807c65e75f35cce8b0d302273a"
      },
      "is_current": true
    },
    {
      "stake_address": "stake_test17quqxxcdejchr45ec6ezn9wqmepxamrt89x8fw3sewxhpyqlqsg49",
      "target": "drep1ygpuetneftlmufa97hm5mf3xvqpdkyw656hyg6h20qaewtg3csnkc",
      "target_name": null,
      "lovelace": 1500000000,
      "at": {
        "slot": 136923215,
        "epoch": 320,
        "time": "2026-10-21T18:13:35Z",
        "tx_hash": "0b647ee2201883ddbb3ce6835795649c37e164a88e51912217e2c0ce5565758d"
      },
      "is_current": true
    }
  ],
  "total": 2025,
  "limit": 5,
  "offset": 0
}
"""

-- | `GET /activity`, măsurat 2026-10-25. __Un rînd din fiecare fel de eveniment care există pe
-- | preprod__, cules cu `event_type=` pe rînd, nu primele unsprezece dintr-o pagină: altfel
-- | fixtura ar avea numai delegări și înregistrări, care sînt 60 din primele 100.
-- |
-- | Dintre cele treisprezece feluri, două nu s-au întîmplat niciodată aici —
-- | `treasury_withdrawal_enacted` și `committee_resigned` — și lipsesc tocmai pentru că
-- | fixtura e măsurată, nu scrisă.
-- |
-- | Patru rînduri n-au tranzacție și n-au actor: sînt evenimente de GRANIȚĂ DE EPOCĂ, pe care
-- | nu le-a provocat nimeni. Trei n-au țintă. `total` e `null` prin construcție (`D-18`).
activityFixture :: String
activityFixture =
  """
{
  "items": [
    {
      "cursor": "137256846:2:4:0",
      "event_type": "delegation_changed",
      "source": "governance",
      "at": {
        "slot": 137256846,
        "epoch": 321,
        "time": "2026-10-25T14:54:06Z",
        "tx_hash": "f0619b14271fc6e931e319bddf5c0010b8ba992530593cdb395fe039fcd9d629"
      },
      "actor_id": "stake_test1upgxfdn3vdx3fjud2sl8rhvwksm6glhmg7cty2yzsekyyrgm428xq",
      "target_id": "always_abstain"
    },
    {
      "cursor": "137244199:2:1:0",
      "event_type": "drep_registered",
      "source": "governance",
      "at": {
        "slot": 137244199,
        "epoch": 321,
        "time": "2026-10-25T11:23:19Z",
        "tx_hash": "9276042f79cf12c13e4b8664d79302c01055860b3cc8e5fc3d44d9e7210cb567"
      },
      "actor_id": "5064b671634d14cb8d543e71dd8eb437a47efb47b0b22882866c420d",
      "target_id": null
    },
    {
      "cursor": "137243764:4:1:0",
      "event_type": "drep_updated",
      "source": "governance",
      "at": {
        "slot": 137243764,
        "epoch": 321,
        "time": "2026-10-25T11:16:04Z",
        "tx_hash": "357cdeb86b3c727d4150f9f9104fe021a95d9fd3e8fdde0aec68b922f1c7feab"
      },
      "actor_id": "5064b671634d14cb8d543e71dd8eb437a47efb47b0b22882866c420d",
      "target_id": null
    },
    {
      "cursor": "137244309:0:1:0",
      "event_type": "drep_retired",
      "source": "governance",
      "at": {
        "slot": 137244309,
        "epoch": 321,
        "time": "2026-10-25T11:25:09Z",
        "tx_hash": "491a40c060deab507023307b0626e7f932792efb291c056d2047fcbf09de5b7f"
      },
      "actor_id": "5064b671634d14cb8d543e71dd8eb437a47efb47b0b22882866c420d",
      "target_id": null
    },
    {
      "cursor": "137227151:3:2:3244726",
      "event_type": "vote_cast",
      "source": "governance",
      "at": {
        "slot": 137227151,
        "epoch": 321,
        "time": "2026-10-25T06:39:11Z",
        "tx_hash": "cf0ff083197e6178790b3ab21438b9fe9f70b920d648840d51242fa20aca58ab"
      },
      "actor_id": "e77eb965c537895a4163322915846b3b57780d97f3107ff0285dc82f",
      "target_id": "131"
    },
    {
      "cursor": "136473457:6:3:0",
      "event_type": "gov_action_proposed",
      "source": "governance",
      "at": {
        "slot": 136473457,
        "epoch": 319,
        "time": "2026-10-16T13:17:37Z",
        "tx_hash": "04f23439388432a22b6830425d0a8114a168ac5ead2767fe122eb956e8593f44"
      },
      "actor_id": "stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4",
      "target_id": "131"
    },
    {
      "cursor": "129686402:-1:7:109",
      "event_type": "gov_action_ratified",
      "source": "governance",
      "at": {
        "slot": null,
        "epoch": 304,
        "time": "2026-07-30T00:00:02Z",
        "tx_hash": null
      },
      "actor_id": null,
      "target_id": "109"
    },
    {
      "cursor": "130118424:-1:8:109",
      "event_type": "gov_action_enacted",
      "source": "governance",
      "at": {
        "slot": null,
        "epoch": 305,
        "time": "2026-08-04T00:00:24Z",
        "tx_hash": null
      },
      "actor_id": null,
      "target_id": "109"
    },
    {
      "cursor": "137030441:-1:9:124",
      "event_type": "gov_action_expired",
      "source": "governance",
      "at": {
        "slot": null,
        "epoch": 321,
        "time": "2026-10-23T00:00:41Z",
        "tx_hash": null
      },
      "actor_id": null,
      "target_id": "124"
    },
    {
      "cursor": "133574403:-1:10:117",
      "event_type": "gov_action_dropped",
      "source": "governance",
      "at": {
        "slot": null,
        "epoch": 313,
        "time": "2026-09-13T00:00:03Z",
        "tx_hash": null
      },
      "actor_id": null,
      "target_id": "117"
    },
    {
      "cursor": "96856972:6:5:0",
      "event_type": "committee_authorized",
      "source": "governance",
      "at": {
        "slot": 96856972,
        "epoch": 228,
        "time": "2025-07-15T00:42:52Z",
        "tx_hash": "c7a1a3eb5c362e6ca951461b660c3ebd9cfcd6f1e7dc853d3fc9dd639b9e508c"
      },
      "actor_id": "70d20c66e0d63c9a638d9230310b4fba988f620ab1a41654e66f167c",
      "target_id": "cedf596dbc94e2229ec11118ea9404f2336369c4826219253e4b6802"
    }
  ],
  "total": null,
  "limit": 11,
  "offset": 0,
  "next_cursor": "137243903:1:1:0"
}
"""

-- | `GET /profiles?limit=6`, măsurat 2026-10-25. Cîmpurile pe care ecranul le citește; restul
-- | (slot, hash de bloc) sînt în răspuns și nu sînt aici, pentru că o fixtură e pentru decodor,
-- | nu o copie a bazei. Jumătate din profiluri n-au credențial de guvernanță, ceea ce e cazul
-- | normal: un profil poate exista fără să pretindă o identitate pe lanț.
profileListFixture :: String
profileListFixture =
  """
{
  "items": [
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0f4eff1d656b5121ca32657f23a4295986f0d9bea7391655b9c020043",
      "name": "palmares-smoke-20261024T205314Z-subject",
      "description": "subject profile for smoke-20261024T205314Z",
      "image_uri": "ipfs://palmares-smoke-placeholder",
      "kind": "person_d_rep",
      "credential": "drep1yfdqa29j3hhsf9lsj490j59t7cgf0k5la5q8nqgkqkahpwq5hl35n",
      "credential_is_script": false,
      "claimant_count": 6
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0de31c9a96041fdeafb91d5d8f6b24f26826b3d740c4fc40090ffcae9",
      "name": "palmares-smoke-20261024T205314Z-issuer",
      "description": "issuer profile for smoke-20261024T205314Z",
      "image_uri": "ipfs://palmares-smoke-placeholder",
      "kind": "auditor",
      "credential": null,
      "credential_is_script": null,
      "claimant_count": null
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b06e4117ca2181d9382c0719e1782c8141abbcb58633b4bf180cd1458b",
      "name": "palmares-smoke-20261024T192629Z-subject",
      "description": "subject profile for smoke-20261024T192629Z",
      "image_uri": "ipfs://palmares-smoke-placeholder",
      "kind": "person_d_rep",
      "credential": "drep1yfdqa29j3hhsf9lsj490j59t7cgf0k5la5q8nqgkqkahpwq5hl35n",
      "credential_is_script": false,
      "claimant_count": 6
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b03e7345404e3b0c0b795ac2d545f5eea7c1d3831261f386a225aafb0a",
      "name": "palmares-smoke-20261024T192629Z-issuer",
      "description": "issuer profile for smoke-20261024T192629Z",
      "image_uri": "ipfs://palmares-smoke-placeholder",
      "kind": "auditor",
      "credential": null,
      "credential_is_script": null,
      "claimant_count": null
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b034a141578feb8318767614d9b1e0f3d9e747a4d37cc4ce40a3dc25e0",
      "name": "palmares-smoke-20261024T175134Z-subject",
      "description": "subject profile for smoke-20261024T175134Z",
      "image_uri": "ipfs://palmares-smoke-placeholder",
      "kind": "person_d_rep",
      "credential": "drep1yfdqa29j3hhsf9lsj490j59t7cgf0k5la5q8nqgkqkahpwq5hl35n",
      "credential_is_script": false,
      "claimant_count": 6
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0132c592ca23fb2334e0a0a1132306d50c174002626a523a522a88649",
      "name": "palmares-smoke-20261024T175134Z-issuer",
      "description": "issuer profile for smoke-20261024T175134Z",
      "image_uri": "ipfs://palmares-smoke-placeholder",
      "kind": "auditor",
      "credential": null,
      "credential_is_script": null,
      "claimant_count": null
    }
  ],
  "total": 12,
  "limit": 6,
  "offset": 0
}
"""

-- | `GET /attestations?limit=6`, măsurat 2026-10-25. `accepted` e al SUBIECTULUI, iar cele trei
-- | numere de dispute sînt separate tocmai pentru că „neacceptată" și „contestată" nu sînt
-- | același lucru.
attestationListFixture :: String
attestationListFixture =
  """
{
  "items": [
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000010708aa68abb20aa664efe2f68a46d4dc28c0ffe5f20b3dbd01b7ecc9df5",
      "subject": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0f4eff1d656b5121ca32657f23a4295986f0d9bea7391655b9c020043",
      "issuer": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0de31c9a96041fdeafb91d5d8f6b24f26826b3d740c4fc40090ffcae9",
      "kind": "audit_passed",
      "date": "2026-10-24T21:11:39Z",
      "accepted": false,
      "name": "smoke-20261024T205314Z-unresolvable",
      "description": "unresolvable anchor for smoke-20261024T205314Z",
      "dispute_count": 0,
      "open_dispute_count": 0,
      "upheld_dispute_count": 0
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.00001070ef7917d1f7cfea84f171d00db00b741a50303bd18c9c170b62a62225",
      "subject": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0f4eff1d656b5121ca32657f23a4295986f0d9bea7391655b9c020043",
      "issuer": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0de31c9a96041fdeafb91d5d8f6b24f26826b3d740c4fc40090ffcae9",
      "kind": "milestone_delivered",
      "date": "2026-10-24T21:09:47Z",
      "accepted": false,
      "name": "smoke-20261024T205314Z-anchored",
      "description": "anchored attestation for smoke-20261024T205314Z",
      "dispute_count": 0,
      "open_dispute_count": 0,
      "upheld_dispute_count": 0
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.0000107051c34a05faa589d9ea5707dbbd366bd3df5a6338f042a7241c1f4a3f",
      "subject": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0f4eff1d656b5121ca32657f23a4295986f0d9bea7391655b9c020043",
      "issuer": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0de31c9a96041fdeafb91d5d8f6b24f26826b3d740c4fc40090ffcae9",
      "kind": "role_held",
      "date": "2026-10-24T20:58:30Z",
      "accepted": true,
      "name": "palmares-smoke-20261024T205314Z-attestation",
      "description": "attestation for smoke-20261024T205314Z",
      "dispute_count": 1,
      "open_dispute_count": 0,
      "upheld_dispute_count": 1
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.0000107086c39b42ae97c949ff998da0ec3b721204cf1cb5395961b5f60821ea",
      "subject": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0f4eff1d656b5121ca32657f23a4295986f0d9bea7391655b9c020043",
      "issuer": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0f4eff1d656b5121ca32657f23a4295986f0d9bea7391655b9c020043",
      "kind": "credential_claim",
      "date": "2026-10-24T20:57:02Z",
      "accepted": false,
      "credential": "drep1yfdqa29j3hhsf9lsj490j59t7cgf0k5la5q8nqgkqkahpwq5hl35n",
      "name": "credential claim for smoke-20261024T205314Z",
      "description": "binds the subject profile to its DRep credential",
      "dispute_count": 0,
      "open_dispute_count": 0,
      "upheld_dispute_count": 0
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.0000107020216e9e05b7df72d4343b1defc8414d31c3749e34145ae8d140ccff",
      "subject": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b06e4117ca2181d9382c0719e1782c8141abbcb58633b4bf180cd1458b",
      "issuer": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b03e7345404e3b0c0b795ac2d545f5eea7c1d3831261f386a225aafb0a",
      "kind": "audit_passed",
      "date": "2026-10-24T19:39:58Z",
      "accepted": false,
      "name": "smoke-20261024T192629Z-unresolvable",
      "description": "unresolvable anchor for smoke-20261024T192629Z",
      "dispute_count": 0,
      "open_dispute_count": 0,
      "upheld_dispute_count": 0
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000010700ac278b7708337dd0cec39516a8aad00e3576133ccc8dc8103741dab",
      "subject": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b06e4117ca2181d9382c0719e1782c8141abbcb58633b4bf180cd1458b",
      "issuer": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b03e7345404e3b0c0b795ac2d545f5eea7c1d3831261f386a225aafb0a",
      "kind": "milestone_delivered",
      "date": "2026-10-24T19:38:28Z",
      "accepted": false,
      "name": "smoke-20261024T192629Z-anchored",
      "description": "anchored attestation for smoke-20261024T192629Z",
      "dispute_count": 0,
      "open_dispute_count": 0,
      "upheld_dispute_count": 0
    }
  ],
  "total": 19,
  "limit": 6,
  "offset": 0
}
"""

-- | `GET /disputes?limit=5`, măsurat 2026-10-25. Toate cele cinci dispute de pe preprod.
disputeListFixture :: String
disputeListFixture =
  """
{
  "items": [
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000020e019fd9551ab85480b95ed2c9ddb7524c1c6e56cb76f4d2f98a12f33db",
      "target": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.0000107051c34a05faa589d9ea5707dbbd366bd3df5a6338f042a7241c1f4a3f",
      "opened_by": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0de31c9a96041fdeafb91d5d8f6b24f26826b3d740c4fc40090ffcae9",
      "opened_at": "2026-10-24T21:06:38Z",
      "stale_after": "2026-11-23T21:06:38Z",
      "deposit": 5000000,
      "verdict": "upheld",
      "name": "palmares-smoke-20261024T205314Z-dispute",
      "description": "dispute for smoke-20261024T205314Z"
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000020e04f1c2fa3758cb1fbf7cd8f1fbf036380b0bf6cb4f2aac2289477f6b7",
      "target": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000010709304948f55376ea52eb1a3dbfd787bdf20cb142234898414b28eb84b",
      "opened_by": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b03e7345404e3b0c0b795ac2d545f5eea7c1d3831261f386a225aafb0a",
      "opened_at": "2026-10-24T19:35:35Z",
      "stale_after": "2026-11-23T19:35:35Z",
      "deposit": 5000000,
      "verdict": "upheld",
      "name": "palmares-smoke-20261024T192629Z-dispute",
      "description": "dispute for smoke-20261024T192629Z"
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000020e01a026d3f300a144b2513c3b2989155b812e226a884dac78480b9ff72",
      "target": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000010707cfa7e4aba15edf44209fbd61d4fcd09128665bb03eb252d0030474f",
      "opened_by": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0132c592ca23fb2334e0a0a1132306d50c174002626a523a522a88649",
      "opened_at": "2026-10-24T18:01:34Z",
      "stale_after": "2026-11-23T18:01:34Z",
      "deposit": 5000000,
      "verdict": "upheld",
      "name": "palmares-smoke-20261024T175134Z-dispute",
      "description": "dispute for smoke-20261024T175134Z"
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000020e0f19eed926d13ac48fbc9da693b041bf96d570fd71d7274c9e74e994d",
      "target": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.0000107014bea12cce2cea6371bc05f68943d44473fdf2ff70a663b4cdf8fbe1",
      "opened_by": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0ec46f39a0b71260adb17ba380beba56820bf8d5d8ef176c22aa84618",
      "opened_at": "2026-10-24T17:10:23Z",
      "stale_after": "2026-11-23T17:10:23Z",
      "deposit": 5000000,
      "verdict": "upheld",
      "name": "palmares-smoke-20261024T170127Z-dispute",
      "description": "dispute for smoke-20261024T170127Z"
    },
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000020e043695b1d8df106b42eda0b7bff1fff2ed2b17e516bde0ee6918cd05b",
      "target": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000010701cec17070d82d79cfb93664dbe6d3cf4b8191d47bea1bc5f009d814a",
      "opened_by": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0a53448cfa801d630b3f25c300d0211b22c7585efceab9838993082bf",
      "opened_at": "2026-10-24T16:40:49Z",
      "stale_after": "2026-11-23T16:40:49Z",
      "deposit": 5000000,
      "verdict": "upheld",
      "name": "palmares-smoke-20261024T163239Z-dispute",
      "description": "dispute for smoke-20261024T163239Z"
    }
  ],
  "total": 5,
  "limit": 5,
  "offset": 0
}
"""

-- | Un singur profil, pentru `GET /profiles/{id}`. E primul din `profileListFixture`, ca linkul
-- | din card sa duca in bundle-ul demo la un profil care EXISTA in lista de deasupra lui.
profileDetailFixture :: String
profileDetailFixture =
  """
{
  "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0f4eff1d656b5121ca32657f23a4295986f0d9bea7391655b9c020043",
  "name": "palmares-smoke-20261024T205314Z-subject",
  "description": "subject profile for smoke-20261024T205314Z",
  "image_uri": "ipfs://palmares-smoke-placeholder",
  "kind": "person_d_rep",
  "credential": "drep1yfdqa29j3hhsf9lsj490j59t7cgf0k5la5q8nqgkqkahpwq5hl35n",
  "credential_is_script": false,
  "claimant_count": 6,
  "slot": 137280273,
  "block_hash": "41f7db42e235aa400456cb50ba6b4519fc33889c4551807fb66c20855e0c0a65"
}
"""

-- | O atestare cu disputele ei, pentru `GET /attestations/{id}`. E PRIMA din
-- | `attestationListFixture`, si subiectul/emitentul ei sint primele doua profiluri din
-- | `profileListFixture` — ca in bundle-ul demo linkurile paginii sa duca la lucruri care EXISTA.
-- |
-- | Are o dispută decisă intentionat: altfel secțiunea de provocări n-ar avea ce randa, iar
-- | tocmai ea e motivul pentru care pagina asta e o singură cerere.
attestationDetailFixture :: String
attestationDetailFixture =
  """
{
  "attestation": {
    "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000010708aa68abb20aa664efe2f68a46d4dc28c0ffe5f20b3dbd01b7ecc9df5",
    "subject": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0f4eff1d656b5121ca32657f23a4295986f0d9bea7391655b9c020043",
    "issuer": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0de31c9a96041fdeafb91d5d8f6b24f26826b3d740c4fc40090ffcae9",
    "kind": "audit_passed",
    "date": "2026-10-24T21:11:39Z",
    "claimed_period": [ "2025-01-01T00:00:00Z", "2025-12-31T00:00:00Z" ],
    "credential": null,
    "accepted": false,
    "name": "smoke-20261024T205314Z-unresolvable",
    "description": "unresolvable anchor for smoke-20261024T205314Z",
    "image_uri": "ipfs://palmares-smoke-placeholder",
    "other_metadata": [],
    "slot": 137280366,
    "block_hash": "d411899af3f25e72d25b703ad775872630c460c0135e28824ddb19c6caf7e39f",
    "tx_hash": "fe7bf7a1bfe7963d4beeed1d4c4b5c8914e085fb310c5f866a017786ad62c2d3",
    "output_index": 0,
    "dispute_count": 1,
    "open_dispute_count": 0,
    "upheld_dispute_count": 0
  },
  "disputes": [
    {
      "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000020e052db653ab132a1a314476882f4be6fc918c67659dc39b9d26a2675ae",
      "target": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000010708aa68abb20aa664efe2f68a46d4dc28c0ffe5f20b3dbd01b7ecc9df5",
      "opened_by": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0de31c9a96041fdeafb91d5d8f6b24f26826b3d740c4fc40090ffcae9",
      "opened_at": "2026-10-26T12:26:58Z",
      "stale_after": "2026-10-26T12:31:58Z",
      "deposit": 5000000,
      "verdict": "expired",
      "name": "flows-1793017633063-dispute",
      "description": "contested from the browser",
      "image_uri": "ipfs://palmares-flows-dispute",
      "slot": 137334776,
      "block_hash": "67800a09567e8b1bf1d1c474b1928c78b4f2f84f1a88e58480c9a5045cb527fc"
    }
  ],
  "level1_anchor": null
}
"""

-- | O singura provocare, pentru `GET /disputes/{id}`. Ruta intoarce chiar forma `DisputeRow`,
-- | deci nu e nevoie de niciun tip nou. E PRIMUL rind din `disputeListFixture`, verbatim, ca un
-- | clic in lista sa duca in bundle-ul demo la aceeasi provocare.
disputeDetailFixture :: String
disputeDetailFixture =
  """
{
  "id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000020e019fd9551ab85480b95ed2c9ddb7524c1c6e56cb76f4d2f98a12f33db",
  "target": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.0000107051c34a05faa589d9ea5707dbbd366bd3df5a6338f042a7241c1f4a3f",
  "opened_by": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000643b0de31c9a96041fdeafb91d5d8f6b24f26826b3d740c4fc40090ffcae9",
  "opened_at": "2026-10-24T21:06:38Z",
  "stale_after": "2026-11-23T21:06:38Z",
  "deposit": 5000000,
  "verdict": "upheld",
  "name": "palmares-smoke-20261024T205314Z-dispute",
  "description": "dispute for smoke-20261024T205314Z",
  "image_uri": "ipfs://palmares-smoke-placeholder",
  "slot": 137280366,
  "block_hash": "d411899af3f25e72d25b703ad775872630c460c0135e28824ddb19c6caf7e39f"
}
"""
