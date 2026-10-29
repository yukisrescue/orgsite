<?php
/**
 * Structured WordPress events for the existing Docker -> Promtail -> Loki path.
 * Keep credentials, attempted usernames, request bodies and error messages out
 * of logs. Error codes and HTTP status are sufficient for dashboard counts.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

function yukis_observability_log( $event, $fields = array() ) {
	$line = wp_json_encode( array_merge( array( 'event' => $event ), $fields ) );
	if ( false !== $line ) {
		error_log( 'YUKIS_OBSERVABILITY ' . $line );
	}
}

add_action(
	'wp_login',
	function ( $user_login, $user ) {
		yukis_observability_log( 'login_success', array( 'user_id' => (int) $user->ID ) );
	},
	10,
	2
);

add_action(
	'wp_login_failed',
	function ( $username, $error ) {
		$code = $error instanceof WP_Error ? $error->get_error_code() : 'unknown';
		yukis_observability_log( 'login_denied', array( 'reason' => $code ) );
	},
	10,
	2
);

add_filter(
	'rest_post_dispatch',
	function ( $response, $server, $request ) {
		if ( ! in_array( $request->get_method(), array( 'POST', 'PUT', 'PATCH', 'DELETE' ), true ) ) {
			return $response;
		}

		$status = (int) $response->get_status();
		if ( $status < 400 ) {
			return $response;
		}

		$data = $response->get_data();
		$code = is_array( $data ) && isset( $data['code'] ) && is_string( $data['code'] )
			? $data['code']
			: 'unknown';

		yukis_observability_log(
			'write_failed',
			array(
				'method' => $request->get_method(),
				'route'  => $request->get_route(),
				'status' => $status,
				'code'   => $code,
			)
		);

		return $response;
	},
	10,
	3
);
